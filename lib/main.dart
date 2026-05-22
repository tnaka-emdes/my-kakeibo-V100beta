import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MaterialApp(home: ReceiptPicker()));

class ReceiptPicker extends StatefulWidget {
  const ReceiptPicker({super.key});
  @override
  State<ReceiptPicker> createState() => _ReceiptPickerState();
}

class _ReceiptPickerState extends State<ReceiptPicker> {
  String _result = "解析方法を選んでください";
  bool _isLoading = false;
  Uint8List? _imageBytes; // 選択された画像を保持

  // 設定・コントローラー
  String _currentApiKey = "";
  String _currentRules = "";
  final TextEditingController _modelController = TextEditingController(
    text: 'gemini-2.5-flash',
  );
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _apiKeyInputController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadInitialSettings();
  }

  Future<void> _loadInitialSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentApiKey = prefs.getString('gemini_api_key') ?? "";
      _currentRules = prefs.getString('analysis_rules') ?? "";
    });
    if (_currentApiKey.isEmpty) _showApiKeyDialog();
  }

  // ①＆② 画像を取得する関数
  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _result = source == ImageSource.camera
            ? "写真を撮影しました。青ボタンで解析を開始します。"
            : "画像を選択しました。青ボタンで解析を開始します。";
      });
    }
  }

  // 解析処理（画像・テキスト両対応）
  Future<void> _analyze() async {
    if (_currentApiKey.isEmpty || _currentRules.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("設定を確認してください")));
      return;
    }

    setState(() {
      _isLoading = true;
      _result = "AIが解析中です...";
    });

    try {
      final model = GenerativeModel(
        model: _modelController.text,
        apiKey: _currentApiKey,
      );
      final List<Content> content = [];

      String finalPrompt =
          "$_currentRules\n\n解析対象テキスト: ${_textController.text}";

      if (_imageBytes != null) {
        content.add(
          Content.multi([
            TextPart(finalPrompt),
            DataPart('image/jpeg', _imageBytes!),
          ]),
        );
      } else {
        content.add(Content.text(finalPrompt));
      }

      final response = await model.generateContent(content);

      setState(() {
        _result = response.text ?? "結果が得られませんでした。";
        // 【追加】解析が終わったら画像を消去し、テキスト入力もリセットする
        _imageBytes = null;
        _textController.clear();
      });
    } catch (e) {
      setState(() => _result = "エラー: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI家計簿 Ver 1.00B"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showRulesDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // モデル選択
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: "Model",
                border: OutlineInputBorder(),
              ),
            ),
          ),

          // テキスト入力（画像への補足指示としても使えます）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: TextField(
              controller: _textController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "テキスト入力 / 画像への補足指示",
                hintText: "テキストのみ、または画像と一緒に送る指示を入力",
                border: OutlineInputBorder(),
              ),
            ),
          ),

          // 画像プレビュー
          if (_imageBytes != null)
            Stack(
              alignment: Alignment.topRight,
              children: [
                Container(
                  height: 150,
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  child: Image.memory(_imageBytes!, fit: BoxFit.contain),
                ),
                // 画像をキャンセルするボタン
                CircleAvatar(
                  backgroundColor: Colors.white,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => setState(() {
                      _imageBytes = null;
                      _result = "解析方法を選んでください";
                    }),
                  ),
                ),
              ],
            ),

          // 解析結果表示
          Expanded(
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(_result),
                      ),
                    ),
            ),
          ),
        ],
      ),

      // 右側に縦並びのボタン
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // 青ボタンがすべての解析（画像 or テキスト）のトリガ
          FloatingActionButton(
            onPressed: _analyze,
            heroTag: 'run',
            backgroundColor: Colors.blueAccent,
            tooltip: "解析実行",
            child: const Icon(Icons.auto_awesome),
          ),
          const SizedBox(height: 16),

          FloatingActionButton(
            onPressed: () => _pickImage(ImageSource.camera),
            heroTag: 'cam',
            tooltip: "カメラで撮影",
            child: const Icon(Icons.camera_alt),
          ),
          const SizedBox(height: 12),

          FloatingActionButton(
            onPressed: () => _pickImage(ImageSource.gallery),
            heroTag: 'gal',
            tooltip: "画像を選択",
            child: const Icon(Icons.photo_library),
          ),
          const SizedBox(height: 12),

          FloatingActionButton(
            onPressed: _copyToClipboard,
            heroTag: 'cp',
            backgroundColor: Colors.grey,
            mini: true,
            child: const Icon(Icons.copy),
          ),
        ],
      ),
    );
  }

  void _showApiKeyDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("APIキーの初期設定"),
        content: TextField(
          controller: _apiKeyInputController,
          decoration: const InputDecoration(
            hintText: "Gemini API Keyを入力してください",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (_apiKeyInputController.text.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(
                  'gemini_api_key',
                  _apiKeyInputController.text,
                );
                if (!mounted) return; // 警告対策：画面が存在するかチェック
                setState(() => _currentApiKey = _apiKeyInputController.text);
                Navigator.pop(context);
              }
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  void _showRulesDialog() {
    final controller = TextEditingController(
      text: _currentRules.isEmpty
          ? "あなたは優秀な家計簿アシスタントです。支出を分類して要約してください。"
          : _currentRules,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ルール設定の編集"),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: "AIへの指示（ルール）を入力してください",
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("キャンセル"),
          ),
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('analysis_rules', controller.text);
              if (!mounted) return;
              setState(() => _currentRules = controller.text);
              Navigator.pop(context);
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard() {
    if (_result.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _result));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('クリップボードにコピーしました！')));
    }
  }
}
