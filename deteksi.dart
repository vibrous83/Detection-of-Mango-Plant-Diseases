import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'hasil_deteksi.dart';

class HalamanDeteksi extends StatefulWidget {
  const HalamanDeteksi({super.key});

  @override
  State<HalamanDeteksi> createState() => _HalamanDeteksiState();
}

class _HalamanDeteksiState extends State<HalamanDeteksi> {
  File? _selectedImage; // Menyimpan gambar yang dipilih
  String? _selectedSource; // Menyimpan pilihan: kamera / galeri
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(String source) async {
    XFile? pickedFile;

    if (source == 'kamera') {
      pickedFile = await _picker.pickImage(source: ImageSource.camera);
    } else {
      pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    }

    if (!mounted) return; //biar gak crash saat user pindah halaman

    if (pickedFile != null) {
      final String ext = pickedFile.name.split('.').last.toLowerCase();
      final List<String> allowed = ['jpg', 'jpeg', 'png'];

      if (!allowed.contains(ext)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gambar yang diunggah tidak sesuai format'),
          ),
        );
        return;
      }

      setState(() {
        _selectedImage = File(pickedFile!.path);
        _selectedSource = source;
      });
    } 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Deteksi Penyakit Daun Mangga',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 15, 132, 33),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Pilih sumber:',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Tombol Kamera
            ElevatedButton.icon(
              onPressed: () => _pickImage('kamera'),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Pilih dari Kamera'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: const Color.fromARGB(255, 15, 132, 33),
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),

            // Tombol Galeri
            ElevatedButton.icon(
              onPressed: () => _pickImage('galeri'),
              icon: const Icon(Icons.photo_library),
              label: const Text('Pilih dari Galeri'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: const Color.fromARGB(255, 15, 132, 33),
                foregroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 30),

            // Preview gambar
            if (_selectedImage != null)
              Column(
                children: [
                  Image.file(_selectedImage!, height: 200, fit: BoxFit.cover),
                  const SizedBox(height: 10),
                  Text(
                    'Gambar dipilih dari: ${_selectedSource!.toUpperCase()}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),

            const SizedBox(height: 30),

            // Tombol Deteksi
            ElevatedButton(
              onPressed: () {
                if (_selectedImage == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Pilih gambar terlebih dahulu'),
                    ),
                  );
                  return;
                }

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HasilDeteksi(
                      selectedSource: _selectedSource!,
                      selectedImage: _selectedImage!,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 55),
                backgroundColor: const Color.fromARGB(255, 15, 132, 33),
              ),
              child: const Text(
                'Deteksi',
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
