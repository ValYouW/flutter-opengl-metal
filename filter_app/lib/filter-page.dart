import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

class FilterPage extends StatefulWidget {
  const FilterPage({Key? key}) : super(key: key);

  @override
  _FilterPageState createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  double _radius = 0;

  final Completer<dynamic> _filterLoader = Completer<dynamic>();

  @override
  void initState() {
    super.initState();

    init();
  }

  init() async {
    // Load the image from the embedded assets
    const imageProvider = AssetImage('assets/drawable/matterhorn.jpg');
    var stream = imageProvider.resolve(ImageConfiguration.empty);

    // create a promise that will be resolved once the image is loaded
    final Completer<ImageInfo> completer = Completer<ImageInfo>();
    var listener = ImageStreamListener((ImageInfo info, bool _) {
      completer.complete(info);
    });

    // listen to the image loaded event
    stream.addListener(listener);

    // wait for the image to be loaded
    final imageInfo = await completer.future;

    // Convert the image bytes to raw rgba
    final rgba = await imageInfo.image.toByteData(format: ImageByteFormat.rawRgba);

    // This is important to release memory within the image stream
    stream.removeListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder(
                future: _filterLoader.future,
                builder: (context, snapshot) {
                  return snapshot.hasData
                      ? Container(
                          color: Colors.green,
                        )
                      : const Center(
                          child: CircularProgressIndicator(),
                        );
                },
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
}
