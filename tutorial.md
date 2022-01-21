# Overview
In this tutorial we will see how to run OpenGL and Metal filters in Flutter.

In this example we will run a simple box blur filter, we will control the blur radius using a slider in the app.

# Starter Project
This tutorial is built upon a starter app, you can get the starter app by cloning this repo and checking out to tag `tutorial-start-here`.

In the starter project we have the `filter-page.dart` in which we just load an image from the app's embedded assets (`init() async {...}`), and we render a simple UI with a placeholder for our image, and a slider that will control the blur radius.

# Creating the filter plugin
Our filter code is going to reside in a separate plugin, lets create it:
```
flutter create
```
