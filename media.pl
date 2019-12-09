#!/usr/bin/perl

use strict;
use DBI;
use JSON;
use Image::ExifTool ':Public';
use File::Find;
use Data::Printer;
use Data::Dumper;
use Digest::MD5;

sub connect_database {
  my $driver = "SQLite";
  my $database = "media.db";
  my $dsn = "DBI:$driver:dbname=$database";
  my $userid = "";
  my $password = "";
  my $dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1 })
    or die $DBI::errstr;
  return $dbh;
}

sub digest_from_file($) {
  my $file = @_[0];
  my $md5 = Digest::MD5->new;
  open(my $F, $file) or die $!;
  return Digest::MD5->new->addfile($F)->hexdigest;
}

sub hash_to_json($) {
  my %info = %{@_[0]};
  my %ihash;
  my $json = JSON->new();

  $json->pretty(1);

  foreach (sort keys %info) {
    my $val = $info{$_};
    my ($year, $month, $day, $rest);

    # change DateTime values into a format SQLite can understand
    if ($_ =~ "Date") {
      if (($year, $month, $day, $rest) = $val =~ /^(\d{4}):(\d{2}):(\d{2}) (.*)$/) {
        $val = "$year-$month-$day $rest";
      }
    }
    if (ref $val eq 'ARRAY') {
      $val = join(', ', @$val);
    } elsif (ref $val eq 'SCALAR') {
      $val = '(binary)';
    }
    $ihash{$_} = $val;
  }
  return $json->encode(\%ihash);
}

sub insert_into_db($$$$$$$$$$$$$) {
  my ($dbh, $path, $filename, $ext, $size, $mtime, $digest, $exif, $width, $height, $duration, $lat, $lon) = @_;
  my $sql = qq[INSERT INTO media(path, filename, ext, size, mtime, digest, exif, width, height, duration, lat, lon)
                      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)];
  my $sth = $dbh->prepare($sql);
  $sth->execute($path, $filename, $ext, $size, $mtime, $digest, $exif, $width, $height, $duration, $lat, $lon)
    or die $DBI::errstr;
}

# converts a string to seconds, possible variants
# 8.24 s
# 0:07:00
# returns number of seconds
sub duration_to_seconds($) {
  my ($s) = @_;
  my ($hour, $min, $sec, $msec);

  if (($sec) = $s =~ /^([.\d]+) s$/) {
    # don't do anything just now
  } elsif (($hour, $min, $sec) = $s =~ /^(\d{1,2}):(\d{2}):(\d{2})$/) {
    # don't do anything just now
  } else {
    die "'$s': I don't understand this string";
  }
  print "Duration=", ($hour * 3600 + $min * 60 + $sec), "sec\n";
  return ($hour * 3600 + $min * 60 + $sec);
}

sub get_height(%) {
  my (%info) = @_;
  my $h = $info{'ImageHeight'};
  if (!defined($h)) {
    $h = $info{'ExifImageHeight'};
  }
  # print "height=$h\n";
  return $h;
}

sub get_width(%) {
  my (%info) = @_;
  my $w = $info{'ImageWidth'};
  if (!defined($w)) {
    $w = $info{'ExifImageWidth'};
  }
  # print "width=$w\n";
  return $w;
}

# get fileextension, can be jpg or jpeg, webm, m2ts, mts etc.
sub get_extension($) {
  my ($fname) = @_;
  my $ext = '';

  my $dot = rindex($fname, '.');
  if ($dot > -1) {
    $ext = lc substr($fname, $dot+1);
  }
  # print "ext=$ext\n";
  return $ext;
}

sub process_file($$) {
  my ($dbh, $fname) = @_;
  my ($duration, $width, $height, $seconds, $json_exif, $digest, @st, $info, $ext, $lat, $lon);

  if ($fname =~ /Program Files/) {
    print "ignored: $fname\n";
    return;
  }

  if ($fname =~ /ProgramData/) {
    print "ignored: $fname\n";
    return;
  }

  if ($fname =~ /\$Recycle.Bin/) {
    print "ignored: $fname\n";
    return;
  }
  
  @st = stat($fname); # file size
  if ($st[7] < (64 * 1024)) {
    print "ignored: $File::Find::name\n";
    return;
  }

  $info = ImageInfo($fname);

  $duration = %$info{'Duration'};
  $seconds = duration_to_seconds($duration) if $duration;

  $width = get_width(%$info);
  $height = get_height(%$info);
  $ext = get_extension($fname);
  $lat = %$info{'GPSLatitude'};
  $lon = %$info{'GPSLongitude'};
  $json_exif = hash_to_json($info);
  $digest = digest_from_file($File::Find::name);
  insert_into_db($dbh, $File::Find::name, $_, $ext, $st[7], $st[9], $digest, $json_exif,
                 $width, $height, $seconds, $lat, $lon);
}

# main starts here

my $dir = shift || ".";

print "start in directory=$dir\n";

my $dbh = connect_database();

find(sub {
  if (-f and /\.(jpeg|jpg|png|mts|m2ts|avi|webm|mp4|mks|mkv)$/i) {
    print "$File::Find::name\n";
    process_file($dbh, $File::Find::name);
  }
}, $dir);

$dbh->disconnect();
__DATA__
select path, (select j.value from json_each(t.exif) AS j WHERE j.key = 'CreateDate') AS data from media as t where data is null;
