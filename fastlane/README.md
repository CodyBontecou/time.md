fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios info

```sh
[bundle exec] fastlane ios info
```

Show current app info on App Store Connect

### ios build

```sh
[bundle exec] fastlane ios build
```

Build iOS app for App Store

### ios upload

```sh
[bundle exec] fastlane ios upload
```

Upload iOS build to App Store Connect

### ios ship

```sh
[bundle exec] fastlane ios ship
```

Build and upload iOS

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload metadata only

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload screenshots only

### ios upload_all

```sh
[bundle exec] fastlane ios upload_all
```

Upload metadata + screenshots

### ios submit

```sh
[bundle exec] fastlane ios submit
```

Submit for review

----


## Mac

### mac info

```sh
[bundle exec] fastlane mac info
```

Show current app info on App Store Connect

### mac build

```sh
[bundle exec] fastlane mac build
```

Build macOS app for App Store

### mac upload

```sh
[bundle exec] fastlane mac upload
```

Upload macOS build to App Store Connect

### mac ship

```sh
[bundle exec] fastlane mac ship
```

Build and upload macOS

### mac upload_metadata

```sh
[bundle exec] fastlane mac upload_metadata
```

Upload metadata only

### mac upload_screenshots

```sh
[bundle exec] fastlane mac upload_screenshots
```

Upload screenshots only

### mac upload_all

```sh
[bundle exec] fastlane mac upload_all
```

Upload metadata + screenshots

### mac submit

```sh
[bundle exec] fastlane mac submit
```

Submit for review

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
