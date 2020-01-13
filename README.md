## OpenMapTiles [![Build Status](https://travis-ci.org/openmaptiles/openmaptiles.svg?branch=master)](https://travis-ci.org/openmaptiles/openmaptiles)

## Fork Overview

I use OpenMapTiles with a [custom topographic
fork](https://github.com/nst-guide/osm-liberty-topo) of the popular [OSM
Liberty](https://github.com/maputnik/osm-liberty) style for the National Scenic
Trails Guide project.

Fork changes:

- Encodes waterways and trails into the vector tiles at a lower zoom than the
  original OpenMapTiles project, so that they can be displayed when more zoomed
  out.
- Adds `natural=spring` and `amenity=drinking_water` to the POI layer.

## Generating tiles

I've found that changing `QUICKSTART_MAX_ZOOM` in `.env` doesn't change the
actual zoom output _when the `.osm.pbf` extract already exists_. It's a good
idea to set `QUICKSTART_MAX_ZOOM` to a lower level like 7 to make sure the
OpenMapTiles docker toolchain is working on your computer.

After you've made sure that OpenMapTiles is working, delete the `.osm.pbf`
extract from the `data/` folder, change `QUICKSTART_MAX_ZOOM`, and then run
`./quickstart` again.

More documentation is in `QUICKSTART.md`.

### Hosting on S3

I use S3 + Cloudflare for fast, cheap hosting of map tiles.
[(Great tutorial for using S3 for serverless map hosting)](https://github.com/addresscloud/serverless-tiles)
OpenMapTiles should
generate an output file like `data/tiles.mbtiles`. To upload to S3, first
convert that `.mbtiles` to a directory of individual tiles with [`mb-util`](https://github.com/mapbox/mbutil):
```
mb-util tiles.mbtiles tiles --image_format=pbf
```
Note that you must provide `--image_format=pbf`, otherwise the individual files
will have `.png` extensions.

Then once you have a directory of files, you can recursively upload to S3 with
```bash
aws s3 cp tiles s3://{bucket_name}/openmaptiles/ \
    --recursive \
    --content-type application/x-protobuf \
    --content-encoding "gzip" \
    --cache-control "public, max-age=2592000, stale-while-revalidate=31536000"
```
I've found that the tiles won't display properly if the `--content-encoding
"gzip"` tag isn't set. You should edit the `cache-control` to something suitable
for your project. I don't plan to update the OSM maps more than once a month, so
this caching should help keep bandwidth costs down.

### Combining multiple geographies

I'm interested in combining OSM data from multiple Geofabrik regions, but I
don't want to use the next higher level in the hierarchy. For example, I want to
render California, Oregon, and Washington, but not all of the US or even
US-west.

There are a couple possible ways to do this.

1. After you run `./quickstart.sh` for each region, move the generated `.mbtiles` file out of the `data/` directory (the `.mbtiles` files are removed at the beginning of each run of `./quickstart.sh`). Then once you have multiple generated `.mbtiles` files, use [`tile-join` (within the Tippecanoe project)](https://github.com/mapbox/tippecanoe) to join them into a single `.mbtiles` file. Then finally run `mb-util` as above to export to a single directory.

    It should look something like this:

    ```bash
    git clone https://github.com/nst-guide/openmaptiles.git
    cd ./openmaptiles
    # Download all necessary OpenMapTiles programs
    docker-compose pull
    # Download and import Geofabrik extracts
    ./quickstart.sh washington
    mv data/tiles.mbtiles ./washington.mbtiles
    ./quickstart.sh oregon
    mv data/tiles.mbtiles ./oregon.mbtiles
    ./quickstart.sh california
    mv data/tiles.mbtiles ./california.mbtiles
    # Join the separate mbtiles into one
    # tile-join comes from tippecanoe
    # https://github.com/mapbox/tippecanoe
    tile-join -o joined.mbtiles washington.mbtiles oregon.mbtiles california.mbtiles
    # Export the mbtiles into a directory
    # https://github.com/mapbox/mbutil
    mb-util joined.mbtiles tiles
    # Upload the directory of tiles to S3
    aws s3 cp tiles s3://{bucket_name}/openmaptiles/ \
        --recursive \
        --content-type application/x-protobuf \
        --content-encoding "gzip" \
        --cache-control "public, max-age=2592000, stale-while-revalidate=31536000"
    ```

2. Since I'm using S3 for static tile hosting, you could probably generate each state, export each `.mbtiles` file to a directory, then upload each directory individually, though I haven't tested this. Something like:

    ```bash
    git clone https://github.com/nst-guide/openmaptiles.git
    cd ./openmaptiles
    # Download all necessary OpenMapTiles programs
    docker-compose pull
    # Run for washington
    ./quickstart.sh washington
    mb-util data/tiles.mbtiles washington
    aws s3 cp washington s3://{bucket_name}/openmaptiles/ \
        --recursive \
        --content-type application/x-protobuf \
        --content-encoding "gzip" \
        --cache-control "public, max-age=2592000, stale-while-revalidate=31536000"

    # Run for oregon
    ./quickstart.sh oregon
    mb-util data/tiles.mbtiles oregon
    aws s3 cp oregon s3://{bucket_name}/openmaptiles/ \
        --recursive \
        --content-type application/x-protobuf \
        --content-encoding "gzip" \
        --cache-control "public, max-age=2592000, stale-while-revalidate=31536000"

    # Run for california
    ./quickstart.sh california
    mb-util data/tiles.mbtiles california
    aws s3 cp california s3://{bucket_name}/openmaptiles/ \
        --recursive \
        --content-type application/x-protobuf \
        --content-encoding "gzip" \
        --cache-control "public, max-age=2592000, stale-while-revalidate=31536000"
    ```

3. You could also try importing multiple `.osm.pbf` files _before generating
    the vector tiles_. I haven't tried this method in detail either. Note that
    you might need to manually modify the bbox and name within
    `data/docker-compose-config.yml`.

    This _should_ be a valid way to import multiple OSM extracts into the
    Postgres instance within the docker setup. You should be able to import as
    many extracts as you have disk space for, and then run the vector tile
    creation on the complete database.

    I'd recommend reading `quickstart.sh` in more detail, as that contains all
    these steps with some comments.

    ```bash
    osm_area="washington"
    testdata=${osm_area}.osm.pbf
    # Downloads Geofabrik data, imports it, and then also creates `docker-compose-config.yml`?
    docker-compose run --rm import-osm  ./download-geofabrik.sh ${osm_area}
    make clean
    docker-compose up -d postgres
    make forced-clean-sql
    docker-compose run --rm import-water
    docker-compose run --rm import-osmborder
    docker-compose run --rm import-natural-earth
    docker-compose run --rm import-lakelines
    docker-compose run --rm import-osm
    docker-compose run --rm import-wikidata
    docker-compose run --rm import-sql
    make psql-analyze

    # Then do the above steps again for more osm_areas before generating the vector tiles.

    docker-compose up -d postserve
    # Use pre-computed docker-compose-config.yml here?
    docker-compose -f docker-compose.yml -f ./data/docker-compose-config.yml  run --rm generate-vectortiles
    docker-compose run --rm openmaptiles-tools  generate-metadata ./data/tiles.mbtiles
    docker-compose run --rm openmaptiles-tools  chmod 666         ./data/tiles.mbtiles
    docker-compose stop postgres
    ```

## Using generated tiles

To use these tiles, you'll need to add a `tile.json` file that describes the
data you've generated. This should conform to the [Tile JSON
specification](https://github.com/mapbox/tilejson-spec/tree/master/2.2.0).

It should look something like this, though you'll need to change the `tiles`
endpoint and update the `maxzoom`, `bounds`, and `center` for your own data
extract:
```json
{
    "tilejson": "2.2.0",
    "name": "openmaptiles",
    "description": "OpenMapTiles",
    "version": "0.1.0",
    "attribution": "<a href=\"https://openmaptiles.org/\" target=\"_blank\">© OpenMapTiles</a> <a href=\"https://www.openstreetmap.org/copyright\" target=\"_blank\">© OpenStreetMap contributors</a>",
    "scheme": "xyz",
    "tiles": [
        "https://{bucket_name}/openmaptiles/{z}/{x}/{y}.pbf"
    ],
    "minzoom": 0,
    "maxzoom": 14,
    "bounds": [-125.3321, 23.8991, -65.7421, 49.4325],
    "center": [-120.673828, 48.864681, 1]
}
```

Then any time you'd pass a mapbox source, like
`mapbox://styles/mapbox/streets-v11`, instead pass the URL to your own
`tile.json` file.

## OpenMapTiles Overview

OpenMapTiles is an extensible and open tile schema based on the OpenStreetMap. This project is used to generate vector tiles for online zoomable maps. OpenMapTiles is about creating a beautiful basemaps with general layers containing topographic information. More information [openmaptiles.org](https://openmaptiles.org/) and [openmaptiles.com](https://openmaptiles.com/).

We encourage you to collaborate, reuse and adapt existing layers, or add your own layers. You may use our approach for your own vector tile project. Feel free to fork the repo and experiment. The repository is built on top of the [openmaptiles/openmaptiles-tools](https://github.com/openmaptiles/openmaptiles-tools) to simplify vector tile creation.

Please keep in mind that OpenMapTiles schema should display general topographic content. If creating a new layer or expanding an existing layer with a specific theme, please create a fork and invite other community members to cooperate on your topic. OpenMapTiles schema is used in many projects all over the world and the size of the final vector tiles needs to be considered in any update.

- :link: Schema https://openmaptiles.org/schema
- :link: Docs https://openmaptiles.org/docs
- :link: Production package: https://openmaptiles.com/production-package/
- :link: Hosting https://www.maptiler.com/cloud/
- :link: Create own layer https://github.com/openmaptiles/openmaptiles-skiing
- :link: Discuss at the #openmaptiles channel at [OSM Slack](https://osmus-slack.herokuapp.com/)

## Styles

You can start from several GL styles supporting the OpenMapTiles vector schema.

:link: [Learn how to create Mapbox GL styles with Maputnik and OpenMapTiles](http://openmaptiles.org/docs/style/maputnik/).

- [OSM Liberty Topo](https://github.com/nst-guide/osm-liberty-topo)
- [OSM Liberty](https://github.com/maputnik/osm-liberty)
- [OSM Bright](https://github.com/openmaptiles/osm-bright-gl-style)
- [Positron](https://github.com/openmaptiles/positron-gl-style)
- [Dark Matter](https://github.com/openmaptiles/dark-matter-gl-style)
- [Klokantech Basic](https://github.com/openmaptiles/klokantech-basic-gl-style)
- [Klokantech 3D](https://github.com/openmaptiles/klokantech-3d-gl-style)
- [Fiord Color](https://github.com/openmaptiles/fiord-color-gl-style)
- [Toner](https://github.com/openmaptiles/toner-gl-style)

We also ported over our favorite old raster styles (TM2).

:link: [Learn how to create TM2 styles with Mapbox Studio Classic and OpenMapTiles](http://openmaptiles.org/docs/style/mapbox-studio-classic/).

- [Light](https://github.com/openmaptiles/mapbox-studio-light.tm2/)
- [Dark](https://github.com/openmaptiles/mapbox-studio-dark.tm2/)
- [OSM Bright](https://github.com/openmaptiles/mapbox-studio-osm-bright.tm2/)
- [Pencil](https://github.com/openmaptiles/mapbox-studio-pencil.tm2/)
- [Woodcut](https://github.com/openmaptiles/mapbox-studio-woodcut.tm2/)
- [Pirates](https://github.com/openmaptiles/mapbox-studio-pirates.tm2/)
- [Wheatpaste](https://github.com/openmaptiles/mapbox-studio-wheatpaste.tm2/)

## Schema

OpenMapTiles consists out of a collection of documented and self contained layers you can modify and adapt.
Together the layers make up the OpenMapTiles tileset.

:link: [Study the vector tile schema](http://openmaptiles.org/schema)

- [aeroway](https://openmaptiles.org/schema/#aeroway)
- [boundary](https://openmaptiles.org/schema/#boundary)
- [building](https://openmaptiles.org/schema/#building)
- [housenumber](https://openmaptiles.org/schema/#housenumber)
- [landcover](https://openmaptiles.org/schema/#landcover)
- [landuse](https://openmaptiles.org/schema/#landuse)
- [mountain_peak](https://openmaptiles.org/schema/#mountain_peak)
- [park](https://openmaptiles.org/schema/#park)
- [place](https://openmaptiles.org/schema/#place)
- [poi](https://openmaptiles.org/schema/#poi)
- [transportation](https://openmaptiles.org/schema/#transportation)
- [transportation_name](https://openmaptiles.org/schema/#transportation_name)
- [water](https://openmaptiles.org/schema/#water)
- [water_name](https://openmaptiles.org/schema/#water_name)
- [waterway](https://openmaptiles.org/schema/#waterway)

## Develop

To work on OpenMapTiles you need Docker.

- Install [Docker](https://docs.docker.com/engine/installation/). Minimum version is 1.12.3+.
- Install [Docker Compose](https://docs.docker.com/compose/install/). Minimum version is 1.7.1+.

### Build

Build the tileset.

```bash
git clone https://github.com/openmaptiles/openmaptiles.git
cd openmaptiles
# Build the imposm mapping, the tm2source project and collect all SQL scripts
make
```

You can execute the following manual steps (for better understanding)
or use the provided `quickstart.sh` script.

```
./quickstart.sh
```

### Prepare the Database

Now start up the database container.

```bash
docker-compose up -d postgres
```

Import external data from [OpenStreetMapData](http://osmdata.openstreetmap.de/), [Natural Earth](http://www.naturalearthdata.com/) and [OpenStreetMap Lake Labels](https://github.com/lukasmartinelli/osm-lakelines).

```bash
docker-compose run import-water
docker-compose run import-natural-earth
docker-compose run import-lakelines
docker-compose run import-osmborder
```

**[Optional]**
Import latest Wikidata. If an OSM feature has [Key:wikidata](https://wiki.openstreetmap.org/wiki/Key:wikidata), OpenMapTiles check corresponding item in Wikidata and use its [labels](https://www.wikidata.org/wiki/Help:Label) for languages listed in [openmaptiles.yaml](openmaptiles.yaml). So the generated vector tiles includes multi-languages in name field.

Beware that current [Wikidata dump](https://dumps.wikimedia.org/wikidatawiki/entities/latest-all.json.gz) is more than 55GB, it takes time to download and import it. If you just want to have a quickstart on OpenMapTiles, just skip this step.

```bash
make download-wikidata
docker-compose run import-wikidata
```

[Download OpenStreetMap data extracts](http://download.geofabrik.de/) and store the PBF file in the `./data` directory.

```bash
cd data
wget http://download.geofabrik.de/europe/albania-latest.osm.pbf
```

[Import OpenStreetMap data](https://github.com/openmaptiles/openmaptiles-tools/tree/master/docker/import-osm) with the mapping rules from
`build/mapping.yaml` (which has been created by `make`).

```bash
docker-compose run import-osm
```

### Work on Layers

Each time you modify layer SQL code run `make` and `make import-sql`.

```
make clean
make
make import-sql
```

Now you are ready to **generate the vector tiles**. Using environment variables
you can limit the bounding box and zoom levels of what you want to generate (`docker-compose.yml`).

```
docker-compose run generate-vectortiles
```

## License

All code in this repository is under the [BSD license](./LICENSE.md) and the cartography decisions encoded in the schema and SQL are licensed under [CC-BY](./LICENSE.md).

Products or services using maps derived from OpenMapTiles schema need to visibly credit "OpenMapTiles.org" or reference "OpenMapTiles" with a link to https://openmaptiles.org/. Exceptions to attribution requirement can be granted on request.

For a browsable electronic map based on OpenMapTiles and OpenStreetMap data, the
credit should appear in the corner of the map. For example:

[© OpenMapTiles](https://openmaptiles.org/) [© OpenStreetMap contributors](https://www.openstreetmap.org/copyright)

For printed and static maps a similar attribution should be made in a textual
description near the image, in the same fashion as if you cite a photograph.
