import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:file_saver/file_saver.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:http/io_client.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:stack_trace/stack_trace.dart';



void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: PDFEditor(),
    );
  }
}

class PDFEditor extends StatefulWidget {
  @override
  _PDFEditorState createState() => _PDFEditorState();
}



class NoProxyHttpClient extends http.BaseClient {
  final HttpClient _httpClient = HttpClient()
    ..findProxy = (uri) => 'DIRECT';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final ioClient = IOClient(_httpClient);
    return ioClient.send(request);
  }
} // Extend http.BaseClient


class NoProxyMultipartRequest extends http.MultipartRequest {
  NoProxyMultipartRequest(String method, Uri url)
      : super(method, url);

  @override
  Future<http.StreamedResponse> send() {
    final noProxyClient = NoProxyHttpClient();
    return noProxyClient.send(this);
  }
} // Extend http.MultipartRequest




class PageInfo {
  final int pageIndex;
  int rotation;
  bool isDeleted; // Flag per indicare se la pagina è cancellata

  PageInfo(this.pageIndex, {this.rotation = 0, this.isDeleted = false});
}

class _PDFEditorState extends State<PDFEditor> {
  pdfrx.PdfDocument? _pdfDocument;


  void _log(String message) {
    final timestamp = DateTime.now().toLocal().toString().substring(11, 16); // hh:mm formato
    final logMessage = '$timestamp: $message';
    if (_debug) {
      print(message);
            _logContent.add(logMessage);
    }
  }

  
  // inizializza le variabili  
  List<int> _selectedPages = [];
  Map<int, img.Image> _rotatedImages = {};
  bool _debug = false;
  String _status = 'Carica un documento PDF';
  String _PDFopened = '';
  List<PageInfo> _pagesInfo = [];
  Map<int, img.Image> _pagePreviews = {};
  bool _showEightPages = true;
  Timer? _clearSelectionTimer; // Aggiunta del timer
  // widget di avanzamento
  double _progress = 0.0;
  bool _isProcessing = false;
  List<String> _logContent = []; // struttura che contiene le linee di log
  

  void _startClearSelectionTimer() {
    // per avviare il timer che deseleziona dopo un timeout
    _clearSelectionTimer?.cancel(); // Annulla il timer precedente, se esiste
    _clearSelectionTimer = Timer(Duration(seconds: 5), () {
      setState(() {
        _selectedPages.clear();
      });
    });
  }
  
  void _toggleEightPagesView() {
    setState(() {
      _showEightPages = !_showEightPages;
    });
  }


  void _togglePageDeletion(int pageIndex) {
    // Funzione per aggiungere o rimuovere pagine dalla lista di cancellazione
    setState(() {
      _pagesInfo[pageIndex].isDeleted = !_pagesInfo[pageIndex].isDeleted;
      if (_pagesInfo[pageIndex].isDeleted) {
        // Aggiungi la "X" rossa sull'immagine
        _rotatedImages[pageIndex] = _drawRedX(_pagePreviews[pageIndex]!);
      } else {
        // Ripristina l'immagine originale senza la "X" rossa
        _rotatedImages.remove(pageIndex);
      }
    });
    
    
    if (_debug) {
      _log('Pagina ${pageIndex+1} ${_pagesInfo[pageIndex].isDeleted ? 'aggiunta alla' : 'rimossa dalla'} lista di cancellazione');
    }
  }
  
  void _loadPDF() async {
    try {
      _showLoadingDialog(context, 'Caricamento del PDF in corso...');

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result != null) {
        final filePath = result.files.single.path!;  //Risultato del filepicker
        final file = File(filePath);
        final data = await file.readAsBytes();
        final doc = await pdfrx.PdfDocument.openData(data);
        
        setState(() {
          _pdfDocument = doc;
          _pagesInfo = List.generate(doc.pages.length, (index) => PageInfo(index));
          _status = 'Documento PDF caricato';
        });
        _log('PDF caricato: $filePath');
        _PDFopened = filePath;
      } else {
        setState(() {
          _status = 'Nessun file selezionato';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Errore durante il caricamento del PDF: $e';
      });
      _log('Errore durante il caricamento del PDF: $e');
    } finally {
      _hideLoadingDialog(context);
    }
  }

  Future<img.Image?> _extractImage(int pageIndex, {int dpi = 72}) async {
    try {
      final page = _pdfDocument!.pages[pageIndex];
      _log('Rendering della pagina ${pageIndex+1}  a ${dpi} DPI');

      final double scaleFactor = dpi / 72.0;

      final int targetWidth = (page.width * scaleFactor).toInt();
      final int targetHeight = (page.height * scaleFactor).toInt();

      if (_debug) {
        _log('Rendering della pagina ${pageIndex + 1} a $dpi DPI');
      }

      final pdfImage = await page.render(
        fullWidth: page.width.toDouble() * scaleFactor,
        fullHeight: page.height.toDouble() * scaleFactor,
      );
      if (pdfImage == null) {
        throw Exception('Rendering della pagina ${pageIndex+1} ha restituito null');
      }
      _log('Rendering della pagina ${pageIndex+1} completato');

      // Creazione dell'immagine dai pixel
      final img.Image manualImage = img.Image.fromBytes(
        width: pdfImage.width,
        height: pdfImage.height,
        bytes: pdfImage.pixels.buffer,
        format: img.Format.uint8, // Specifica il formato se necessario
        order: img.ChannelOrder.bgra
      );

      if (_debug) {
        // _log('Esempio di pixel della pagina $pageIndex: ${pdfImage.pixels.buffer.asUint8List().take(10).toList()}');
        // Salvataggio dell'immagine su disco per debug
        //final directory = await getTemporaryDirectory();
        //final path = '${directory.path}/page_$pageIndex.png';
        //final file = File(path);
        //file.writeAsBytesSync(img.encodePng(manualImage));
        //_log('Immagine della pagina $pageIndex salvata su $path');
      }

      return manualImage;
    } catch (e) {
      _log('Errore durante l\'estrazione dell\'immagine della pagina $pageIndex: $e');
      return null;
    }
  }


  Future<img.Image?> _rotatePage(int pageIndex, int degrees) async {
    try {
      final image = _pagePreviews[pageIndex];
      if (image != null) {
        // Usa il parametro denominato 'angle' per specificare l'angolo di rotazione
        final rotatedImage = img.copyRotate(image, angle: degrees.toDouble());
        return rotatedImage;
      } else {
        final originalImage = await _extractImage(pageIndex, dpi: 72);
        if (originalImage != null) {
          // Usa il parametro denominato 'angle' per specificare l'angolo di rotazione
          final rotatedImage = img.copyRotate(originalImage, angle: degrees.toDouble());
          return rotatedImage;
        }
      }
      return null;
    } catch (e) {
      _log('Errore durante la rotazione dell\'immagine della pagina $pageIndex: $e');
      return null;
    }
  }




  void _rotateSelectedPages(int degrees) async {
    if (_pdfDocument == null) return;

    try {
      _showLoadingDialog(context, 'Rotazione delle pagine in corso...');

      for (int pageIndex in _selectedPages) {
        final pageInfo = _pagesInfo[pageIndex];
        pageInfo.rotation = (pageInfo.rotation + degrees) % 360;

        if (_debug) {
          _log('Rotazione della pagina ${pageInfo.pageIndex + 1} di $degrees gradi');
        }

        final rotatedImage = await _rotatePage(pageInfo.pageIndex, degrees);
        if (rotatedImage != null) {
          setState(() {
            _rotatedImages[pageInfo.pageIndex] = rotatedImage;
            _pagePreviews[pageInfo.pageIndex] = rotatedImage; // aggiorna anche l'anteprima
          });
          _log('Immagine della pagina ${pageInfo.pageIndex} ruotata e aggiornata nella UI');
        } else {
          _log('Rotazione fallita per la pagina ${pageInfo.pageIndex}');
        }
      }
      setState(() {
        _status = 'Pagine selezionate ruotate';
      });
      _log('Pagine selezionate ruotate con successo');
    } catch (e) {
      setState(() {
        _status = 'Errore durante la rotazione delle pagine: $e';
      });
      _log('Errore durante la rotazione delle pagine: $e');
    } finally {
      _hideLoadingDialog(context);
    }
  }




  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text(message),
            ],
          ),
        );
      },
    );
  }

  void _hideLoadingDialog(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }


  void _deletePages() async {
    if (_pdfDocument == null) return;

    try {
      _showLoadingDialog(context, 'Eliminazione delle pagine in corso...');
      // Implementazione della ligica di cancellazione
       for (int pageIndex in _selectedPages) {
         _togglePageDeletion(pageIndex);
       };
       _log('Pagine selezionate eliminate');
    } catch (e) {
      setState(() {
        _status = 'Errore durante l\'eliminazione delle pagine: $e';
      });
      _log('Errore durante l\'eliminazione delle pagine: $e');
    } finally {
      _hideLoadingDialog(context);
    }
  }


  void _savePDF() async {
    try {
      _showLoadingDialog(context, 'Rendering del documento PDF in corso...');

      final pdf = pw.Document();

      for (var pageInfo in _pagesInfo) {
        if (pageInfo.isDeleted) continue; // Skip deleted pages

        final page = _pdfDocument!.pages[pageInfo.pageIndex];
        const int targetDpi = 300;
        final double scaleFactor = targetDpi / 72.0;

        if (_debug) {
          _log('Rendering della pagina ${pageInfo.pageIndex + 1} a 300 DPI');
        }

        final pdfImage = await page.render(
          fullWidth: page.width.toDouble() * scaleFactor,
          fullHeight: page.height.toDouble() * scaleFactor,
        );

        if (pdfImage != null) {
          final pngData = img.encodePng(
            img.Image.fromBytes(
              width: pdfImage.width,
              height: pdfImage.height,
              bytes: pdfImage.pixels.buffer,
              format: img.Format.uint8, // Specifica il formato se necessario
              order: img.ChannelOrder.bgra
          ));

          if (_debug) {
            _log('Rotazione della pagina ${pageInfo.pageIndex + 1} di ${pageInfo.rotation} gradi');
          }

          final rotatedImage = img.copyRotate(img.decodePng(pngData)!, angle: pageInfo.rotation.toDouble());

          final pdfPage = pw.Page(
            pageFormat: PdfPageFormat(rotatedImage.width.toDouble(), rotatedImage.height.toDouble()),
            build: (context) {
              return pw.Image(
                pw.MemoryImage(Uint8List.fromList(img.encodePng(rotatedImage))),
                fit: pw.BoxFit.cover,
              );
            },
          );

          pdf.addPage(pdfPage);
        }
      }

      _hideLoadingDialog(context);
      _showLoadingDialog(context, 'Salvataggio del documento PDF in corso...');

      final outputDir = await FilePicker.platform.getDirectoryPath();
      if (outputDir != null) { 
        
        final outputPath = path.join(outputDir, path.basename(_PDFopened));
        final file = File(outputPath.replaceFirst('.pdf', '_ed.pdf'));
        await file.writeAsBytes(await pdf.save());

        setState(() {
          _status = 'Documento PDF salvato in $outputPath';
        });
        _log('Documento PDF salvato in $outputPath');
      } else {
        setState(() {
          _status = 'Salvataggio annullato dall\'utente';
        });
        _log('Salvataggio annullato dall\'utente');
      }
    } catch (e) {
      setState(() {
        _status = 'Errore durante il salvataggio del PDF: $e';
      });
      _log('Errore durante il salvataggio del PDF: $e');
    } finally {
      _hideLoadingDialog(context);
    }
  }
  
  Future<void> _performOCR() async {
    _log('Carico file');
    FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
    if (result != null) {
        final filePath = result.files.single.path!;
        _log('Carico file $filePath');
        final file = File(filePath);
        setState(() {
            _status = 'OCR Started';
            _progress = 0.0;
            _isProcessing = true;
          });
        try {
          final url = Uri.parse('http://rustdesk.ssis.sm:8080/api/v1/misc/ocr-pdf');
          final request = NoProxyMultipartRequest('POST', url)
            ..fields['languages'] = 'ita'
            ..fields['sidecar'] = 'false'
            ..fields['deskew'] = 'true'
            ..fields['clean'] = 'true'
            ..fields['cleanFinal'] = 'true'
            ..fields['ocrType'] = 'skip-text'
            ..fields['ocrRenderType'] = 'hocr'
            ..fields['removeImagesAfter'] = 'false'
            ..files.add(await http.MultipartFile.fromPath('fileInput', filePath)
          );
          

          final response = await request.send();          
          _log('Risposta al POST a $url: ${response.statusCode}');
          if (response.statusCode == 200) {
             // Log headers for debugging
            response.headers.forEach((key, value) {
              _log('Header: $key: $value');
            });

            final responseData = await response.stream.toBytes();
            //_log('Received data length: ${responseData.length}');
            // Log the first 100 bytes for debugging
            //_log('First 100 bytes: ${responseData.sublist(0, 100)}');
            _log('Start Writing document $filePath');
            setState(() {
              _status = 'Start Writing document $filePath';
              _progress = 0.5; // Aggiornamento progress
            });

            // Call compress PDF function
            await _compressPDF(responseData, filePath);
          } else {
            _log('OCR failed: ${response.reasonPhrase}');
            setState(() {
              _status = 'OCR failed: ${response.reasonPhrase}';
              _isProcessing = false;
            });
          }
        } catch (e, stackTrace) {
          setState(() {
            _status = 'OCR failed: $e';
            _isProcessing = false;
          });
          final chain = Chain.forTrace(stackTrace).terse;
          _log('OCR failed: $e\nStack trace: $chain');
        }
    }
  }
  
  
   Future<void> _compressPDF(List<int> pdfData, String originalFilePath) async {
    try {
      final url = Uri.parse('http://rustdesk.ssis.sm:8080/api/v1/misc/compress-pdf');
      final request = NoProxyMultipartRequest('POST', url)
        ..fields['optimizeLevel'] = '2'
        ..fields['expectedOutputSize'] = ''
        ..files.add(http.MultipartFile.fromBytes('fileInput', pdfData, filename: 'compressed.pdf', contentType: MediaType('application', 'pdf')));

      final response = await request.send();
      _log('Risposta al POST a $url: ${response.statusCode}');
      if (response.statusCode == 200) {
        final responseData = await response.stream.toBytes();
        _log('Compressed data length: ${responseData.length}');
        setState(() {
          _status = 'Compression successful';
          _progress = 1.0; // Completamento progress
          _isProcessing = false;
        });
        // Save the compressed PDF file
        await saveCompressedPDF(responseData,originalFilePath);
      } else {
        _log('Compression failed: ${response.reasonPhrase}');
        setState(() {
          _status = 'Compression failed: ${response.reasonPhrase}';
          _isProcessing = false;
        });
      }
    } catch (e, stackTrace) {
      setState(() {
        _status = 'Compression failed: $e';
        _isProcessing = false;
      });
      final chain = Chain.forTrace(stackTrace).terse;
      _log('Compression failed: $e\nStack trace: $chain');
    }
  }
  
  Future<void> saveOCRDocument(Uint8List data,FilePickerResult result) async {
    final filePath = result.files.single.path!;
    if ( _debug ) {
      _log('Salvo ${filePath}');
    }
    final path = '${filePath}';
    final file = File(filePath);
    await file.writeAsBytes(data);
    setState(() {
       _status = 'OCR successful written $filePath';
    });

    print('File saved at $path');
  }
  
  Future<void> saveCompressedPDF(List<int> data, String originalFilePath) async {
    final file = File(originalFilePath.replaceFirst('.pdf', '_compressed.pdf'));
    await file.writeAsBytes(data);
    _log('File saved to ${file.path}');
  }

  
  img.Image _drawRedX(img.Image image) {
    // Disegna una X sopra l'immagine 
    // Disegna la linea diagonale da sinistra a destra
    img.drawLine(
      image, 
      x1: 0,
      y1: 0,
      x2: image.width,
      y2: image.height,
      color: img.ColorRgb8(255, 0, 0),
      thickness: 3,
    );
    
    // Disegna la linea diagonale da destra a sinistra
    img.drawLine(
      image, 
      x1: image.width,
      y1: 0,
      x2: 0,
      y2: image.height,
      color: img.ColorRgb8(255, 0, 0),
      thickness: 3,
    );

    return image;
  }

  Widget _buildGridView() {
    // visualizza griglia di anteprime da visualizzare con Expanded 
      return GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 1 / 1.414,
        ),
        itemCount: _pdfDocument!.pages.length,
        itemBuilder: (context, index) {
          final pageInfo = _pagesInfo[index];
          return _buildPagePreview(index, pageInfo);
        },
      );
    }
    
    Widget _buildListView() {
      // visualizza lista di anteprime da visualizzare con Expanded 
      return ListView.builder(
        itemCount: _pdfDocument!.pages.length,
        itemBuilder: (context, index) {
          final pageInfo = _pagesInfo[index];
          return _buildPagePreview(index, pageInfo);
        },
      );
    }

  Widget _buildPagePreview(int index, PageInfo pageInfo) {
    return FutureBuilder<img.Image?>(
      future: _rotatedImages.containsKey(index)
          ? Future.value(_rotatedImages[index])
          : _extractImage(index, dpi: 72),
      builder: (context, snapshot) {
        // Stato di attesa: mostra un indicatore di caricamento
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: EdgeInsets.all(8.0),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        // Stato di errore: mostra un messaggio di errore
        else if (snapshot.hasError) {
          if (_debug) {
            _log('Errore durante il rendering della pagina ${index + 1}: ${snapshot.error}');
          }
          return Container(
            margin: EdgeInsets.all(8.0),
            child: Center(
              child: Text('Errore durante il rendering della pagina ${index + 1}: ${snapshot.error}'),
            ),
          );
        }
        // Stato di dati disponibili: mostra l'immagine della pagina
        else if (snapshot.hasData) {
          final image = snapshot.data!;
          img.Image rotatedImage;

          // Salva l'anteprima dell'immagine nella mappa _pagePreviews
          _pagePreviews[index] = image;

          // Se la pagina è cancellata, disegna una "X" rossa sull'immagine
          if (pageInfo.isDeleted) {
            rotatedImage = _drawRedX(image);
            if (_debug) {
              _log('Pagina ${index + 1} cancellata, disegno una "X" rossa.');
            }
          } else {
            rotatedImage = image;
            if (_debug) {
              _log('Pagina ${index + 1} non cancellata, visualizzazione normale.');
            }
          }

          return GestureDetector(
            onTap: () {
              setState(() {
                // Gestisce la selezione/deselezione della pagina
                if (_selectedPages.contains(index)) {
                  _selectedPages.remove(index);
                  if (_debug) {
                    _log('Pagina ${index + 1} deselezionata.');
                  }
                } else {
                  _selectedPages.add(index);
                  if (_debug) {
                    _log('Pagina ${index + 1} selezionata.');
                  }
                }
                // Annulla il timer precedente e riavvia il timer per deselezionare dopo 3 secondi
                _clearSelectionTimer?.cancel();
                //_startClearSelectionTimer();
              });
            },
            child: Container(
              margin: EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _selectedPages.contains(index) ? Colors.blue : Colors.transparent,
                  width: 3.0,
                ),
              ),
              child: Stack(
                children: [
                  Image.memory(Uint8List.fromList(img.encodePng(rotatedImage))),
                  if (_selectedPages.contains(index))
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Icon(Icons.check_circle, color: Colors.blue),
                    ),
                ],
              ),
            ),
          );
        } else {
          // Stato predefinito: ritorna un contenitore vuoto
          return Container();
        }
      },
    );
  }

  
  
  void _showAboutOverlay(BuildContext context) {
    OverlayState? overlayState = Overlay.of(context);
    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (BuildContext context) {
        return Positioned(
          top: 50.0,
          right: 50.0,
          child: Material(
            elevation: 4.0,
            child: Container(
              width: 300.0,
              padding: EdgeInsets.all(16.0),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('About', style: TextStyle(fontSize: 20.0)),
                  SizedBox(height: 20.0),
                  Text('Informazioni di licenza...\nLicenza Libera\nRealizzato in Flutter da Diego Ercolani 2024 SSIS S.p.A.\nVersione 0 - dedicata a Franca'),
                  SizedBox(height: 20.0),
                  ElevatedButton(
                    onPressed: () {
                      overlayEntry?.remove();
                      _showLogOverlay(context);
                    },
                    child: Text('Log'),
                  ),
                  TextButton(
                    onPressed: () {
                      overlayEntry?.remove();
                    },
                    child: Text('Chiudi'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    overlayState?.insert(overlayEntry);
  }
  
  void _showLogOverlay(BuildContext context) {
    OverlayState? overlayState = Overlay.of(context);
    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (BuildContext context) {
        return Positioned(
          top: 100.0,
          left: 100.0,
          child: Material(
            elevation: 4.0,
            child: Container(
              width: 400.0,
              height: 400.0,
              padding: EdgeInsets.all(16.0),
              color: Colors.white,
              child: Column(
                children: [
                  Text('Log', style: TextStyle(fontSize: 20.0)),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(_logContent.join('\n')),
                    ),                    
                  ),
                  SizedBox(height: 20.0),
                  ElevatedButton(
                    onPressed: _saveLog,
                    child: Text('Salva Log'),
                  ),
                  TextButton(
                    onPressed: () {
                      overlayEntry?.remove();  // Usare ?. per rimuovere
                    },
                    child: Text('Chiudi'),
                  ),
                ],
              ),
            ), // Container
          ) // Material
        );
      }, // builder
      
    );

    overlayState?.insert(overlayEntry);
  }

  void _saveLog() async {
    // Implementa il salvataggio del log, ad esempio utilizzando il file picker o i permessi di scrittura
      try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/log.txt');
      await file.writeAsString(_logContent.join('\n'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Log salvato in ${file.path}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore durante il salvataggio del log: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Editor PDF'),
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _loadPDF,
                child: Text('Carica PDF'),
              ),
              ElevatedButton(
                onPressed: () => _toggleEightPagesView(),
                child: Text('8 pagine'),
              ),
              Spacer(),
              IconButton(
                icon: Icon(Icons.help_outline),
                onPressed: () => _showAboutOverlay(context),
              ),
              Switch(
                value: _debug,
                onChanged: (value) {
                  setState(() {
                    _debug = value;
                    _status = 'Debug ${_debug ? 'attivato' : 'disattivato'}';
                  });
                  _log('Debug ${_debug ? 'attivato' : 'disattivato'}');                  
                },
                activeColor: Colors.blue,
                inactiveThumbColor: Colors.grey,
                
              ),
              Text('Debug'),
            ],
          ),
          if (_pdfDocument != null)
            Expanded(
              child: _showEightPages // visualizza 8 pagine o in grid o in lista
                  ? _buildGridView()
                  : _buildListView(),
            ),
            if (_isProcessing) // Mostra la barra di avanzamento se in corso
              LinearProgressIndicator(value: _progress),
          Text(_status),
          if (_selectedPages.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    _rotateSelectedPages(-90);
                    _startClearSelectionTimer(); // Avvia il timer
                  },
                  child: Row(
                    children: [
                      Icon(Icons.rotate_left),
                      SizedBox(width: 4),
                      Text('Ruota sinistra'),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    _deletePages();
                    _startClearSelectionTimer(); // Avvia il timer
                  },
                  child: Text('Elimina pagine'),
                ),
                ElevatedButton(
                  onPressed: () {
                    _rotateSelectedPages(90);
                    _startClearSelectionTimer(); // Avvia il timer
                  },
                  child: Row(
                    children: [
                      Icon(Icons.rotate_right),
                      SizedBox(width: 4),
                      Text('Ruota destra'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _performOCR,
            child: Icon(Icons.article,
                    color: Colors.pink,
                    size: 24.0,
                    semanticLabel: 'performOCR'
                    ),
                    tooltip: 'Perform OCR',
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            onPressed: _savePDF,
            child: Icon(Icons.save,
                        color: Colors.pink,
                        size: 24.0,
                        semanticLabel: 'Salva il documento'
                        ),
                        tooltip: "Salva il documento",
          ),
       ],
      ),
    );
  }
} // fine classe _PDFEditorState
