import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class HasilDeteksi extends StatefulWidget {
  final String selectedSource;
  final File selectedImage;

  const HasilDeteksi({
    super.key,
    required this.selectedSource,
    required this.selectedImage,
  });

  @override
  State<HasilDeteksi> createState() => _HasilDeteksiState();
}

class _HasilDeteksiState extends State<HasilDeteksi> {
  late Interpreter _interpreter;
  bool _loading = true;
  List<Map<String, dynamic>> _detections = [];
  double _origW = 1;
  double _origH = 1;

  final Map<int, String> _classNames = {
    0: "Anthracnose",
    1: "Sooty Mould",
    2: "Healthy",
  };

  final Map<String, Map<String, dynamic>> _penyakitInfo = {
    "Anthracnose": {
      "deskripsi":
          "Anthracnose merupakan penyakit yang disebabkan oleh jamur Colletotrichum sp. Penyakit ini menyerang daun, ranting, dan buah mangga terutama pada kondisi lembap.",
      "gejala": [
          "Bercak cokelat kehitaman kecil pada daun",
          "Bercak meluas dan menyebabkan daun mengering",
          "Daun gugur prematur dan ranting mati",
          "Buah membusuk sebelum matang",
      ],
      "pencegahan": [
          "Gunakan varietas mangga tahan penyakit",
          "Buang daun dan bagian tanaman terinfeksi",
          "Gunakan Bacillus subtilis sebagai pengendali hayati",
      ],
    },
    "Sooty Mould": {
      "deskripsi":
          "Sooty mould adalah penyakit yang ditandai dengan lapisan hitam seperti jelaga pada permukaan daun akibat embun madu dari serangga penghisap.",
      "gejala": [
          "Daun, ranting, atau buah tampak tertutup jelaga hitam",
          "Daun terinfeksi berat bisa menguning atau rontok",
      ],
      "pencegahan": [
          "Gunakan insektisida abamektin, karbosulfan, atau minyak nimba",
          "Pasang pita perekat di batang untuk mencegah semut",
          "Gunakan fungisida berbahan tembaga atau belerang bila parah",
      ],
    },
    "Healthy": {
      "deskripsi":
          "Daun sehat memiliki warna hijau cerah, bentuk utuh tanpa kerusakan fisik, dan kadar klorofil tinggi yang mendukung fotosintesis optimal",
      "gejala": [""],
      "pencegahan": [""],
    },
  };

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  //Load Model
  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('models/best.tflite');
      await _runInference();
    } catch (e) {
      debugPrint("❌ Gagal memuat model: $e");
    }
  }

  //Preprocess Image
  Future<Map<String, dynamic>> _preprocessImage() async {
    final bytes = await widget.selectedImage
        .readAsBytes(); //baca file (8 bit) dari path
    img.Image? originalImage = img.decodeImage(
      bytes,
    ); //ubah bytes mentah jadi struktur
    if (originalImage == null) return {};

    originalImage = img.bakeOrientation(
      originalImage,
    ); //baca EXIF lalu putar gambar sesuai orientasi

    _origW = originalImage.width.toDouble(); //simpan ukuran asli lebar
    _origH = originalImage.height.toDouble(); //simpan ukuran asli tinggi

    final resizedImage = img.copyResize(
      originalImage,
      width: 640,
      height: 640,
    ); //resize ukuran

    final input = List.generate(
      1, //batch size
      (_) => List.generate(
        640, //baris y
        (y) => List.generate(640, (x) {
          //kolom x
          final p = resizedImage.getPixel(x, y); //ambil pixel
          return [p.r / 255.0, p.g / 255.0, p.b / 255.0]; //normalisasi ke 0-1
        }),
      ),
    );

    return {"input": input, "originalW": _origW, "originalH": _origH};
  }

  //Predict
  Future<List<List<List<double>>>> _predict(List input) async {
    final outChannels = 7; //cx, cy, w, h, kelas 0,1,2
    final anchors = 8400;

    final raw = List.generate(
      1, //batch size
      (_) => List.generate(outChannels, (_) => List.filled(anchors, 0.0)),
    ); //1x7x8400

    _interpreter.run(input, raw);
    return raw;
  }

  //Postprocess
  Future<List<Map<String, dynamic>>> _postProcess(
    List<List<List<double>>> raw,
    double originalW,
    double originalH,
  ) async {
    final outChannels = 7;
    final anchors = 8400;

    List<List<double>> predList = List.generate(
      anchors,
      (i) => List.generate(outChannels, (j) => raw[0][j][i]),
    );

    final confThreshold = 0.5;
    List<Map<String, dynamic>> candidates = []; //untuk box

    for (var row in predList) {
      double cx = row[0];
      double cy = row[1];
      double w = row[2];
      double h = row[3];

      List<double> probs = row.sublist(4, 7); //kelas 0,1,2
      int cls = probs.indexOf(
        probs.reduce(max),
      ); //ambil kelas dengan nilai tertinggi
      double score = probs[cls];

      if (score < confThreshold) continue;

      //konversi koordinat bounding box ke ukuran asli.
      double xmin = (cx - w / 2) * originalW;
      double ymin = (cy - h / 2) * originalH;
      double xmax = (cx + w / 2) * originalW;
      double ymax = (cy + h / 2) * originalH;

      //pastikan box tidak keluar dari gambar
      xmin = xmin.clamp(0.0, originalW);
      ymin = ymin.clamp(0.0, originalH);
      xmax = xmax.clamp(0.0, originalW);
      ymax = ymax.clamp(0.0, originalH);

      if (xmax - xmin < 1 || ymax - ymin < 1) continue;

      //simpan kandidat
      candidates.add({
        "box": Rect.fromLTRB(xmin, ymin, xmax, ymax),
        "score": score,
        "class": cls,
      });
    }

    // IOU
    double iouRect(Rect a, Rect b) {
      final double x1 = max(a.left, b.left);
      final double y1 = max(a.top, b.top);
      final double x2 = min(a.right, b.right);
      final double y2 = min(a.bottom, b.bottom);

      final double interWidth = max(0, x2 - x1);
      final double interHeight = max(0, y2 - y1);
      final double interArea = interWidth * interHeight;

      final double areaA = a.width * a.height;
      final double areaB = b.width * b.height;

      return interArea / (areaA + areaB - interArea + 1e-10); //rumus IOU
    }

    // NMS
    List<Map<String, dynamic>> finalDetections = [];
    final iouThreshold = 0.5;

    for (int clsId = 0; clsId < 3; clsId++) {
      List<Map<String, dynamic>> clsBoxes = candidates
          .where((d) => d["class"] == clsId)
          .toList(); // Ambil semua box yang kelasnya sama (misal semua kelas 0)

      clsBoxes.sort(
        (a, b) => (b["score"] as double).compareTo(
          a["score"] as double,
        ), //urutin tertinggi ke rendah
      );

      //ambil box dengan skor tertinggi
      while (clsBoxes.isNotEmpty) {
        final top = clsBoxes.removeAt(0);
        finalDetections.add(top);

        clsBoxes = clsBoxes.where((d) {
          double iou = iouRect(top["box"], d["box"]);
          return iou < iouThreshold;
        }).toList();
      }
    }

    return finalDetections;
  }

  Future<void> _runInference() async {
    final prep = await _preprocessImage();
    if (prep.isEmpty) return;

    final input = prep["input"];
    final raw = await _predict(input);

    final dets = await _postProcess(raw, prep["originalW"], prep["originalH"]);

    setState(() {
      _detections = dets;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _interpreter.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String detectedClass = "-";
    Map<String, dynamic>? info;

    if (_detections.isNotEmpty) {
      detectedClass = _classNames[_detections.first["class"]] ?? "-";
      info = _penyakitInfo[detectedClass];
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Hasil Deteksi",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0F8421),
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Center(
                    child: InteractiveViewer(
                      child: Stack(
                        children: [
                          SizedBox(
                            width: 320,
                            height: 320,
                            child: FittedBox(
                              fit: BoxFit.fill,
                              child: Image.file(widget.selectedImage),
                            ),
                          ),
                          SizedBox(
                            width: 320,
                            height: 320,
                            child: CustomPaint(
                              painter: BoundingBoxPainter(
                                _detections,
                                _classNames,
                                _origW,
                                _origH,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  /// JENIS PENYAKIT
                  const SizedBox(height: 20),
                  const Text(
                    "Jenis Penyakit:",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detectedClass,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                    ),
                  ),
                  
                  /// DESKRIPSI
                  const SizedBox(height: 20),
                  const Text(
                    "Deskripsi:",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    info?["deskripsi"] ?? "-",
                    textAlign: TextAlign.justify,
                    style: const TextStyle(fontSize: 16),
                  ),

                  const SizedBox(height: 16),

                  /// Gejala
                  const Text(
                    "Gejala:",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 6),

                  SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...(info?["gejala"] as List<dynamic>? ?? ["-"]).map(
                          (g) => Text(
                            "• $g",
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),

                  /// Pencegahan
                  const SizedBox(height: 16),

                  const Text(
                    "Pencegahan:",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 6),

                  SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...(info?["pencegahan"] as List<dynamic>? ?? ["-"]).map(
                          (p) => Text(
                            "• $p",
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<Map<String, dynamic>> detections;
  final Map<int, String> classNames;
  final double origW;
  final double origH;

  BoundingBoxPainter(this.detections, this.classNames, this.origW, this.origH);

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / origW;
    final scaleY = size.height / origH;

    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 14,
      backgroundColor: Colors.red,
    );

    for (var det in detections) {
      Rect raw = det["box"];

      final rect = Rect.fromLTRB(
        raw.left * scaleX,
        raw.top * scaleY,
        raw.right * scaleX,
        raw.bottom * scaleY,
      );

      canvas.drawRect(rect, paint); //gambar bounding box

      final cls = classNames[det["class"]] ?? "Unknown";
      final conf = (det["score"] as double).toStringAsFixed(2);

      final textSpan = TextSpan(text: "$cls ($conf)", style: textStyle);
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);

      tp.layout();
      tp.paint(canvas, Offset(rect.left, rect.top - tp.height));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
