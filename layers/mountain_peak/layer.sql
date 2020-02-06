
-- etldoc: layer_mountain_peak[shape=record fillcolor=lightpink,
-- etldoc:     style="rounded,filled", label="layer_mountain_peak | <z7_> z7+" ] ;

CREATE OR REPLACE FUNCTION layer_mountain_peak(
    bbox geometry,
    zoom_level integer,
    pixel_width numeric)
  RETURNS TABLE(
    osm_id bigint,
    geometry geometry,
    name text,
    wikidata text,
    class text,
    tags hstore,
    ele int,
    "rank" int) AS
$$
   -- etldoc: osm_peak_point -> layer_mountain_peak:z7_
  SELECT
    osm_id,
    geometry,
    name,
    wikidata,
    tags -> 'natural' AS class,
    tags,
    ele::int,
    rank::int FROM (
      SELECT osm_id, geometry, name, wikidata, tags,
      substring(ele from E'^(-?\\d+)(\\D|$)')::int AS ele,
      row_number() OVER (
          PARTITION BY LabelGrid(geometry, 100 * pixel_width)
          ORDER BY (
            (CASE WHEN ele is not null AND ele ~ E'^-?\\d{1,4}(\\D|$)' THEN substring(ele from E'^(-?\\d+)(\\D|$)')::int ELSE 0 END) +
            (CASE WHEN NULLIF(wikipedia, '') is not null THEN 10000 ELSE 0 END) +
            (CASE WHEN NULLIF(name, '') is not null THEN 10000 ELSE 0 END)
          ) DESC
      )::int AS "rank"
      FROM osm_peak_point
      WHERE geometry && bbox
    ) AS ranked_peaks
  WHERE
    (zoom_level >= 7 AND rank <= 1 AND ele is not null) OR
    (zoom_level >= 9 AND rank <= 3 AND ele is not null) OR
    (zoom_level >= 11 AND rank <= 5 AND ele is not null) OR
    (zoom_level >= 14)
  ORDER BY "rank" ASC;

$$
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE;
