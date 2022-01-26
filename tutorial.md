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
Open the Android code for the filter plugin In Android Studio: `filter_plugin\example\android`

## build.gradle settings
1. Open `build.gradle` of the Module `android.app` and change `minSdkVersion` to at least 18. Also change `targetSdkVersion` and `compileSdkVersion` to whatever you like.
1. Open `build.gradle` of `android.filter_plugin` and change as above (`targetSdkVersion` might be missing, that's ok).
1. Sync project with gradle files

## GLUtils
1. Create a new package named `filter`.
1. Create new kotlin file `GLUtils`, it will have some OpenGL util functions we will use
```kt
object GLUtils {
	var VertexShaderSource = """#version 300 es
	// vertex value between 0-1
	in vec2 a_texCoord;

	uniform float u_flipY;

	// Used to pass the texture coordinates to the fragment shader
	out vec2 v_texCoord;

	// all shaders have a main function
	void main() {
		// convert from 0->1 to 0->2
		vec2 zeroToTwo = a_texCoord * 2.0;

		// convert from 0->2 to -1->+1 (clipspace)
		vec2 clipSpace = zeroToTwo - 1.0;

		gl_Position = vec4(clipSpace * vec2(1, u_flipY), 0, 1);

		// pass the texCoord to the fragment shader
		// The GPU will interpolate this value between points.
		v_texCoord = a_texCoord;
	}	"""

	fun createProgram(vertexSource: String, fragmentSource: String): Int {
		val vertexShader = buildShader(GLES30.GL_VERTEX_SHADER, vertexSource)
		if (vertexShader == 0) {
			return 0
		}

		val fragmentShader = buildShader(GLES30.GL_FRAGMENT_SHADER, fragmentSource)
		if (fragmentShader == 0) {
			return 0
		}

		val program = GLES30.glCreateProgram()
		if (program == 0) {
			return 0
		}

		GLES30.glAttachShader(program, vertexShader)
		GLES30.glAttachShader(program, fragmentShader)
		GLES30.glLinkProgram(program)

		return program
	}

	fun createTexture(data: Bitmap?, width: Int, height: Int, internalFormat: Int = GLES30.GL_RGBA, format: Int = GLES30.GL_RGBA, type: Int = GLES30.GL_UNSIGNED_BYTE): Int {
		val texture = IntArray(1)
		GLES30.glGenTextures(1, texture, 0)
		GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, texture[0])

		GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
		GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
		GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_NEAREST)
		GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_NEAREST)

		// Upload the image into the texture.
		val mipLevel = 0 // the largest mip
		val border = 0

		if (data != null) {
			val buffer = ByteBuffer.allocate(data.byteCount)
			data.copyPixelsToBuffer(buffer)
			buffer.position(0)
			GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, mipLevel, internalFormat, width, height, border, format, type, buffer)
		} else {
			GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, mipLevel, internalFormat, width, height, border, format, type, null)
			GLES30.glGetError()
		}

		return texture[0]
	}

	fun checkEglError(msg: String) {
		val error = EGL14.eglGetError()
		if (error != EGL14.EGL_SUCCESS) {
			throw RuntimeException(msg + ": EGL error: 0x" + Integer.toHexString(error))
		}
	}

	private fun buildShader(type: Int, shaderSource: String): Int {
		val shader = GLES30.glCreateShader(type)
		if (shader == 0) {
			return 0
		}

		GLES30.glShaderSource(shader, shaderSource)
		GLES30.glCompileShader(shader)

		val status = IntArray(1)
		GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, status, 0)
		if (status[0] == 0) {
			Log.e("CPXGLUtils", GLES30.glGetShaderInfoLog(shader))
			GLES30.glDeleteShader(shader)
			return 0
		}

		return shader
	}
}
```

## Gaussian Blur Filter

1. Create a new Kotlin class/file name `GaussianBlur`
```kt
class GaussianBlur(private val outSurface: Surface, private val srcImg: Bitmap) {
	private var mEGLDisplay = EGL14.EGL_NO_DISPLAY
	private var mEGLContext = EGL14.EGL_NO_CONTEXT
	private var mEGLSurface = EGL14.EGL_NO_SURFACE

	private var program: Int = -1
	private var attributes: MutableMap<String, Int> = hashMapOf()
	private var uniforms: MutableMap<String, Int> = hashMapOf()
	private var vao: IntArray = IntArray(1)

	private var srcTexture: Int

	// Credit: https://xorshaders.weebly.com/tutorials/blur-shaders-5-part-2
	private val fragmentShader = """#version 300 es
		precision highp float;

		uniform sampler2D u_image;
		in vec2 v_texCoord;
		uniform float u_radius;
		out vec4 outColor;

		const float Directions = 16.0;
		const float Quality = 3.0;
		const float Pi = 6.28318530718; // pi * 2

		void main()
		{
			vec2 normRadius = u_radius / vec2(textureSize(u_image, 0));
			vec4 acc = texture(u_image, v_texCoord);
			for(float d = 0.0; d < Pi; d += Pi / Directions)
			{
				for(float i = 1.0 / Quality; i <= 1.0; i += 1.0 / Quality)
				{
					acc += texture(u_image, v_texCoord + vec2(cos(d), sin(d)) * normRadius * i);
				}
			}

			acc /= Quality * Directions;

			outColor =  acc;
		}
	"""

	init {
		eglSetup()
		makeCurrent()

		programSetup()

		// Create the texture that will hold the source image
		srcTexture = GLUtils.createTexture(srcImg, srcImg.width, srcImg.height)
	}

	private fun eglSetup() {
		// Create EGL display that will output to the given outSurface
		mEGLDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
		if (mEGLDisplay === EGL14.EGL_NO_DISPLAY) {
			throw RuntimeException("unable to get EGL14 display")
		}

		val version = IntArray(2)
		if (!EGL14.eglInitialize(mEGLDisplay, version, 0, version, 1)) {
			throw RuntimeException("unable to initialize EGL14")
		}

		// Configure EGL
		val attribList = intArrayOf(
			EGL14.EGL_COLOR_BUFFER_TYPE, EGL14.EGL_RGB_BUFFER,
			EGL14.EGL_RED_SIZE, 8,
			EGL14.EGL_GREEN_SIZE, 8,
			EGL14.EGL_BLUE_SIZE, 8,
			EGL14.EGL_ALPHA_SIZE, 8,
			EGL14.EGL_LEVEL, 0,
			EGL14.EGL_RENDERABLE_TYPE, /* EGL14.EGL_OPENGL_ES2_BIT,*/ EGLExt.EGL_OPENGL_ES3_BIT_KHR,
			EGL14.EGL_NONE // mark list termination
		)

		val configs = arrayOfNulls<EGLConfig>(1)
		val numConfig = IntArray(1)
		EGL14.eglChooseConfig(mEGLDisplay, attribList, 0, configs, 0, 1, numConfig, 0)
		if (numConfig[0] == 0) {
			throw Exception("No EGL config was available")
		}

		// Configure context for OpenGL ES 3.0.
		val attrib_list = intArrayOf(
			EGL14.EGL_CONTEXT_CLIENT_VERSION, 3,
			EGL14.EGL_NONE
		)

		val sharedCtx = EGL14.EGL_NO_CONTEXT
		mEGLContext = EGL14.eglCreateContext(mEGLDisplay, configs[0], sharedCtx!!, attrib_list, 0)
		GLUtils.checkEglError("eglCreateContext")

		// Create a window surface, and attach it to the Surface we received.
		val surfaceAttribs = intArrayOf(
			EGL14.EGL_NONE
		)

		// create a new EGL window surface, we use the "outSurface" provided to us (by Flutter).
		mEGLSurface = EGL14.eglCreateWindowSurface(mEGLDisplay, configs[0], outSurface, surfaceAttribs, 0)
		GLUtils.checkEglError("eglCreateWindowSurface")
	}

	private fun programSetup() {
		// create the program
		this.program = GLUtils.createProgram(
			GLUtils.VertexShaderSource,
			fragmentShader
		)

		// Get vertex shader attributes
		this.attributes["a_texCoord"] = GLES30.glGetAttribLocation(this.program, "a_texCoord")

		// Find uniforms
		this.uniforms["u_flipY"] = GLES30.glGetUniformLocation(this.program, "u_flipY")
		this.uniforms["u_image"] = GLES30.glGetUniformLocation(this.program, "u_image")
		this.uniforms["u_radius"] = GLES30.glGetUniformLocation(this.program, "u_radius")

		// Create a vertex array object (attribute state)
		GLES30.glGenVertexArrays(1, this.vao, 0)
		// and make it the one we're currently working with
		GLES30.glBindVertexArray(this.vao[0])

		// provide texture coordinates to the vertex shader, we use 2 rectangles that will cover
		// the entire image
		val texCoords = floatArrayOf(
			// 1st triangle
			0f, 0f,
			1f, 0f,
			0f, 1f,
			// 2nd triangle
			0f, 1f,
			1f, 0f,
			1f, 1f
		)

		val texCoordsBuffer = ByteBuffer.allocateDirect(texCoords.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
		texCoordsBuffer.put(texCoords)
		texCoordsBuffer.position(0)

		// Create a buffer to hold the texCoords
		val texCoordBuffer = IntArray(1)
		GLES30.glGenBuffers(1, texCoordBuffer, 0)
		// Bind it to ARRAY_BUFFER (used for Vertex attributes)
		GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, texCoordBuffer[0])
		// upload the text corrds into the buffer
		GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, texCoordsBuffer.capacity() * 4, texCoordsBuffer, GLES30.GL_STATIC_DRAW)
		// turn it "on"
		GLES30.glEnableVertexAttribArray(this.attributes["a_texCoord"]!!)
		// Describe how to pull data out of the buffer, take 2 items per iteration (x and y)
		GLES30.glVertexAttribPointer(this.attributes["a_texCoord"]!!, 2, GLES30.GL_FLOAT, false, 0, 0)
	}

	fun draw(radius: Float, flip: Boolean = false) {
		makeCurrent()

		// Tell it to use our program
		GLES30.glUseProgram(this.program)

		// set u_radius in fragment shader
		GLES30.glUniform1f(this.uniforms["u_radius"]!!, radius)

		GLES30.glUniform1f(this.uniforms["u_flipY"]!!, if (flip) -1f else 1f) // need to y flip for canvas

		// Tell the shader to get the texture from texture unit 0
		GLES30.glUniform1i(this.uniforms["u_image"]!!, 0)
		GLES30.glActiveTexture(GLES30.GL_TEXTURE0 + 0)
		GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, srcTexture)

		// Bind the output frame buffer
		GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)

		GLES30.glViewport(0, 0, srcImg.width, srcImg.height)
		GLES30.glClearColor(0f, 0f, 0f, 0f)
		GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT or GLES30.GL_DEPTH_BUFFER_BIT)

		// Draw the rectangles we put in the vertex shader
		GLES30.glDrawArrays(GLES30.GL_TRIANGLES, 0, 6)

		// This "draw" the result onto the surface we got from Flutter
		EGL14.eglSwapBuffers(mEGLDisplay, mEGLSurface)
		GLUtils.checkEglError("eglSwapBuffers")
	}

	fun destroy() {
		this.srcImg.recycle()

		val texts = intArrayOf(this.srcTexture)
		GLES30.glDeleteTextures(texts.size, texts, 0)

		if (mEGLDisplay !== EGL14.EGL_NO_DISPLAY) {
			EGL14.eglMakeCurrent(mEGLDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
			EGL14.eglDestroySurface(mEGLDisplay, mEGLSurface)
			EGL14.eglDestroyContext(mEGLDisplay, mEGLContext)
			EGL14.eglReleaseThread()
			EGL14.eglTerminate(mEGLDisplay)
		}

		mEGLDisplay = EGL14.EGL_NO_DISPLAY
		mEGLContext = EGL14.EGL_NO_CONTEXT
		mEGLSurface = EGL14.EGL_NO_SURFACE
	}

	private fun makeCurrent() {
		EGL14.eglMakeCurrent(mEGLDisplay, mEGLSurface, mEGLSurface, mEGLContext)
		GLUtils.checkEglError("eglMakeCurrent")
	}
}
```

## FilterPlugin
This file is the Android implementation of our plugin, this is where we will receive calls from "flutter land" and execute them on Android.
```kt
class FilterPlugin: FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel

  private var gaussianBlur: GaussianBlur? = null
  private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null
  private var flutterSurfaceTexture: TextureRegistry.SurfaceTextureEntry? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    // Create a communication channel between flutter land and android
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "vyw/filter_plugin")
    channel.setMethodCallHandler(this)
    this.pluginBinding = flutterPluginBinding
  }

  // This will be called whenever we get message from android land
  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "getPlatformVersion" -> {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
      }
      "create" -> {
        if (pluginBinding == null) {
          result.error("NOT_READY", "pluginBinding is null", null)
          return
        }

        createFilter(call, result)
      }
      "draw" -> {
        if (gaussianBlur != null) {
          // Get the radius param
          val radius: Double = call.argument("radius")!!

          gaussianBlur!!.draw(radius.toFloat(), true)
          result.success(null)
        } else {
          result.error("NOT_INITIALIZED", "Filter not initialized", null)
        }
      }
      "dispose" -> {
        gaussianBlur?.destroy()
        if (flutterSurfaceTexture != null) {
          flutterSurfaceTexture!!.release()
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    this.pluginBinding = null
  }

  private fun createFilter(@NonNull call: MethodCall, @NonNull result: Result) {
    // Get request params
    val width: Int = call.argument("width")!!
    val height: Int = call.argument("height")!!
    val srcImage = call.argument("img") as? ByteArray

    // our response will be a dictionary
    val reply: MutableMap<String, Any> = HashMap()

    if (srcImage != null) {
      // Convert input image to bitmap
      val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
      bmp.copyPixelsFromBuffer(ByteBuffer.wrap(srcImage))

      // Create a Surface for our filter to draw on, it is backed by a texture we get from Flutter
      flutterSurfaceTexture = pluginBinding!!.textureRegistry.createSurfaceTexture()
      val nativeSurfaceTexture = flutterSurfaceTexture!!.surfaceTexture()
      nativeSurfaceTexture.setDefaultBufferSize(width, height)
      val nativeSurface = Surface(nativeSurfaceTexture)

      // create our filter and tell it to draw to the surface we just created (which is backed
      // by the flutter texture)
      gaussianBlur = GaussianBlur(nativeSurface, bmp)
    }

    // Return the flutter texture id to Flutter land, the "Texture" widget in our app will
    // display it
    reply["textureId"] = flutterSurfaceTexture?.id() ?: -1
    result.success(reply)
  }
}
```

# Create the filter api in Flutter
Now we will create the Flutter part of our filter plugin, open the `filter_plugin` project.

## FilterController
This class will provide the api to the app, create file `filter_controller.dart`:
```dart
// Channel to send messages to the native platform land
const MethodChannel _channel = MethodChannel('vyw/filter_plugin');

class FilterController {
  FilterController();

  int _textureId = -1;
  int _width = 0;
  int _height = 0;
  bool _isDisposed = false;
  bool _initialized = false;

  bool get initialized {
    return _initialized;
  }

  int get textureId {
    return _textureId;
  }

  int get width {
    return _width;
  }

  int get height {
    return _height;
  }

  Future<void> initialize(ByteData bytes, int width, int height) async {
    if (_isDisposed) {
      throw Exception('Disposed FilterController');
    }

    _width = width;
    _height = height;

    // Initialize the filter on the native platform
    final params = {'img': bytes.buffer.asUint8List(0), 'width': width, 'height': height};
    final reply = await _channel.invokeMapMethod<String, dynamic>('create', params);
    _initialized = true;
    _textureId = reply!['textureId'];
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    // Dispose the filter on the native platform
    _channel.invokeMethod('dispose');
    _isDisposed = true;
  }

  Future<void> draw(double radius) async {
    if (!_initialized) {
      throw Exception('FilterController not initialized');
    }

    // Call the filter draw method on the native platform
    final params = {'radius': radius};
    await _channel.invokeMethod('draw', params);
  }
}
```

## FilterPreview
This is the widget in which we will render the gpu texture
Create file `filter_preview.dart`:
```dart
class FilterPreview extends StatelessWidget {
  const FilterPreview(this.controller, {Key? key}) : super(key: key);

  final FilterController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.initialized) {
      return Container();
    }

    return AspectRatio(
      aspectRatio: controller.width / controller.height,
      // The flutter Texture widget draws a gpu texture using the texture id we got
      // from the filter native implementation
      child: Texture(
        textureId: controller.textureId,
      ),
    );
  }
}
```

# Use the filter in Flutter app
Back in our `filter_app` update `android/app/build.gradle` with `minSdkVersion` to 18. Also change `targetSdkVersion` and `compileSdkVersion` to whatever you like.

## Add filter_plugin dependency
Back in our `filter_app` add the plugin as dependency to `pubspec.yaml`:
```
dependencies:
  flutter:
    sdk: flutter
filter_plugin:
  path: ../filter_plugin
```

## Use the filter
In `filter-page.dart` add this member to the `_FilterPageState` class:
```dart
FilterController? _controller;
```
Next create a method `initFilterController` as follow:
```dart
// Convert the image bytes to raw rgba
final rgba = await imageInfo.image.toByteData(format: ImageByteFormat.rawRgba);

// Initialize the filter controller
_controller = FilterController();
await _controller!.initialize(rgba!, imageInfo.image.width, imageInfo.image.height);

await _controller!.draw(_radius);

// update ui
setState(() {});
```
Call this method from the `init` method right before the call to `stream.removeListener(listener);` as follow:
```dart
await initFilterController(imageInfo);
```

Finally, we will rewrite the `build` method to use `FilterPreview` as:
```dart
@override
Widget build(BuildContext context) {
  if (_controller == null) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  return Material(
    child: Container(
      color: Colors.white,
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilterPreview(_controller!),
              ],
            ),
          ),
          Row(
            children: [
              const SizedBox(width: 20),
              const Text(
                'Blur',
                style: TextStyle(color: Colors.black, fontSize: 20),
              ),
              Expanded(
                child: Slider(
                  value: _radius,
                  min: 0,
                  max: 20,
                  onChanged: (val) {
                    setState(() {
                      _radius = val;
                      _controller!.draw(_radius);
                    });
                  },
                ),
              )
            ],
          )
        ],
      ),
    ),
  );
}
```
