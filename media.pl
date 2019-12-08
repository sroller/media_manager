#!/usr/bin/perl

use strict;
use DBI;
use JSON;
use Image::ExifTool ':Public';
use File::Find;
# use Data::Printer;
use Digest::MD5;

sub digest_from_file($) {
  my $file = @_[0];
  my $md5 = Digest::MD5->new;
  open(my $F, $file) or die $!;
  return Digest::MD5->new->addfile($F)->hexdigest;
}

sub hash_to_json(%) {
  my %ihash = @_;
}

my $driver = "SQLite";
my $database = "media.db";
my $dsn = "DBI:$driver:dbname=$database";
my $userid = "";
my $password = "";
my $dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1 })
       or die $DBI::errstr;

my $dir = shift || ".";
my %jpgs;
my $json = JSON->new();
$json->pretty(1);

print "dir=$dir\n";

find(sub {
  if (-f and /\.(jpg|mts|m2ts|avi|webm)$/i) {
    print "$File::Find::name\n";
    my $info = ImageInfo($File::Find::name);
    my %ihash;
    foreach (keys %$info) {
      my $val = $$info{$_};
      if (ref $val eq 'ARRAY') {
        $val = join(', ', @$val);
      } elsif (ref $val eq 'SCALAR') {
        $val = '(binary)';
      }
      $ihash{$_} = $val;
    }
    my $digest = digest_from_file($File::Find::name);
    my $exif = $json->encode(\%ihash);
    # $jpgs{$File::Find::name} = [$File::Find::name, $_, $exif]
    my @st = stat($File::Find::name);
    my $sql = qq[INSERT INTO media(path, filename, size, mtime, digest, exif)
                 VALUES (?, ?, ?, ?, ?, ?)];
    my $sth = $dbh->prepare($sql);
    my $rv = $sth->execute($File::Find::name, $_, $st[7], $st[9], $digest, $exif)
             or die $DBI::errstr;
  }
}, $dir);

$dbh->disconnect();
__DATA__
select path, (select j.value from json_each(t.exif) AS j WHERE j.key = 'CreateDate') AS data from media as t where data is null;
