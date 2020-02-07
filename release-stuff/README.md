Release Guide
=============

- Bump version and create a respective commit
- Tag that commit with the version number
- `mbtiny dist` - Generate a release tarball
- `mbtiny upload` - Upload the release to CPAN

The process of building a release on the different platforms is largely automated. There is a build pipeline setup utilizing the CircleCI infrastructure.
The process of building is not started automatically, but has to be triggered manually. To do so one needs to call a special script.

    ./trigger-manual-build.sh 2 afbc1348971234318974523789afc898798d7ecf

The parameters are:
- The version to build, e.g. 2
- A CircleCI personal API token. One can be created here: <https://circleci.com/account/api>
  Do not confuse the personal API token with project specific API tokens! The project specific API tokens will not work and result in a "Permission denied" error.

After calling the above script accordingly a message with some JSON indicating successful start of the build procedure should be printed.
Navigate to <https://circleci.com/gh/Raku/workflows/App-Rakubrew/tree/master> and select the latest workflow named "manual-build". Four build jobs should be running. One for Windows, one for Linux, one for MacOS and one that zips the results together. After successful completion of the jobs click on the "manual-zip-results" job, select the "Artifacts" tab and download the shown file.
- Unzip the file, add a "changes" file with the respective entries, and put that folder on the webserver in `$webroot/releases`

