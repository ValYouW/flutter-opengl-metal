# Overview
In this tutorial we will see how to run OpenGL and Metal filters in Flutter.

In this example we will run a simple box blur filter, we will control the blur radius using a slider in the app.

# Starter Project
This tutorial is built upon a starter app, you can get the starter app by cloning this repo and checking out to tag `tutorial-start-here`.

In the starter project we have the `filter-page.dart` in which we just load an image from the app's embedded assets (`init() async {...}`), and we render a simple UI with a placeholder for our image, and a slider that will control the blur radius.

# Creating the filter plugin
Our filter code is going to reside in a separate plugin, lets create it:
```
flutter create --platforms=android,ios --template=plugin filter_plugin --org com.valyouw
```

# Create the filter in Android
Open the Android code for the filter plugin: `filter_plugin\example\android`

## build.gradle settings
1. Open `build.gradle` of the Module `android.app` and change `minSdkVersion` to at least 18. Also change `targetSdkVersion` and `compileSdkVersion` to whatever you like.
1. Open `build.gradle` of `android.filter_plugin` and change as above (`targetSdkVersion` might be missing, that's ok).
1. Sync project with gradle files

## GLUtils
1. Create a new package named `filter`.
1. Create new kotlin file `GLUtils`, it will have some OpenGL util functions we will use
```kt
// todo: put GLUtils.kt here
```

## Gaussian Blur Filter

1. Create a new Kotlin class/file name `GaussianBlur`
```kt
// Todo: put GaussianBlur.kt here
```

## FilterPlugin
This file is the Android implementation of our plugin, this is where we will receive calls from "flutter land" and execute them on Android.
```kt
// todo: put here FilterPlugin.kt
```