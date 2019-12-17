CREATE TABLE media (
  tstmp DATETIME DEFAULT CURRENT_TIMESTAMP,
  path string PRIMARY KEY,
  filename string,
  ext string,
  size number,
  mtime datetime,
  digest string,
  height int,
  width int,
  duration int,
  datetime_original string,
  lon text,
  lat text,
  camera text,
  exif json);

CREATE INDEX media_path ON media(path);
CREATE INDEX media_digest ON media(digest);
CREATE INDEX media_filename ON media(filename);

.quit

