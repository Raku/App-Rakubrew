Release Guide
=============

- Write a summary of the changes in `Changes`
- Bump version in `lib/App/Rakubrew.pm`
- Create a respective commit
- Tag that commit with the version number
- `mbtiny dist` - Generate a release tarball
- `mbtiny upload` - Upload the release to CPAN
- Trigger compilation of the platform specific packages. The process of
  building a release on the different platforms is largely automated. There is
  a build pipeline setup utilizing the CircleCI infrastructure. The process of
  building is not started automatically, but has to be triggered manually. To
  do so one needs to call a special script:

    ./trigger-manual-build.sh 2 afbc1348971234318974523789afc898798d7ecf

  The parameters are:
  - The version to build, e.g. 2
  - A CircleCI personal API token. One can be created here: <https://circleci.com/account/api>
    Do not confuse the personal API token with project specific API tokens! The
    project specific API tokens will not work and result in a
    "Permission denied" error.

- After calling the above script accordingly, a message with some JSON
  indicating successful start of the build procedure should be printed.
- Navigate to <https://circleci.com/gh/Raku/workflows/App-Rakubrew/tree/master>
  and select the latest workflow named "manual-build". Four build jobs should
  be running. One for Windows, one for Linux, one for MacOS and one that zips
  the results together.
- Wait for the jobs to complete successfully.
- Click on the "manual-zip-results" job, select the "Artifacts" tab and
  download the shown file.
- Unzip the file.
- Add a "changes" file, do so by copying the `Changes` file to `changes` and
  deleting everything except for the entries for the last release. Don't
  include the version number and remove leading spaces.
- The final directory structure should look as follows:

    /2/changes
    /2/perl/rakubrew
    /2/macos/rakubrew
    /2/win/rakubrew.exe

- Upload that folder to the webserver and put it in the releases folder.
- Verify that the new version is displayed on <https://rakubrew.org/>.

