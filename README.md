# Archiving this repo since GoCD has in built support for PostgreSQL and the paid PostgreSQL addon is no longer supported.

# Migration-test

This test checks the user scenario of migrating GoCD server from a H2 database to PostgreSQL database

## Requirements

* Ruby
* Rake
* Docker

## Run instruction

To run it locally, create an `addons` folder in the checkout folder, download and place the postgres addon jar in it. Also place the latest `addon_builds.json` file in the same location and then run,

`GO_VERSION=X.X.X rake test_migration`

# License

```
Copyright 2019 ThoughtWorks, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

```
