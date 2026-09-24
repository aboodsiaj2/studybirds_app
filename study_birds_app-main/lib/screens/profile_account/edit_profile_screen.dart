import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/feature_ui.dart';
import '../../core/student_repository.dart';

class EditProfileScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  const EditProfileScreen({super.key, this.onSaved});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const fields = {
    'englishFullName': 'الاسم بالإنجليزية',
    'phone': 'رقم الهاتف',
    'nationality': 'الجنسية',
    'currentResidenceCountry': 'بلد الإقامة',
    'passportNumber': 'رقم جواز السفر',
    'dateOfBirth': 'تاريخ الميلاد (YYYY-MM-DD)',
    'currentEducation': 'الدراسة الحالية',
    'gpa': 'المعدل الدراسي',
    'englishTest.exam': 'اختبار اللغة الإنجليزية',
    'englishTest.score': 'النتيجة',
    'targetCountries': 'الدول المستهدفة (افصل بفاصلة)',
    'preferredFields': 'المجالات المفضلة (افصل بفاصلة)',
    'preferredDegreeLevel': 'الدرجة الدراسية المطلوبة',
    'intake': 'موعد بدء الدراسة',
    'studyBudget.min': 'الميزانية الدنيا',
    'studyBudget.max': 'الميزانية القصوى',
    'studyBudget.currency': 'عملة الميزانية',
    'guardianContact.name': 'اسم ولي الأمر',
    'guardianContact.relationship': 'صلة القرابة',
    'guardianContact.phone': 'هاتف ولي الأمر',
    'guardianContact.email': 'بريد ولي الأمر',
    'emergencyContact.name': 'اسم جهة اتصال الطوارئ',
    'emergencyContact.relationship': 'صلة القرابة للطوارئ',
    'emergencyContact.phone': 'هاتف الطوارئ',
    'address': 'العنوان',
    'bio': 'نبذة',
  };
  final controllers = {
    for (final key in fields.keys) key: TextEditingController()
  };
  final form = GlobalKey<FormState>();
  Map<String, dynamic> profile = {};
  String level = '';
  bool loading = true, saving = false, loaded = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await StudentRepository.instance.getProfile() ?? {};
      if (!mounted) return;
      profile = value;
      loaded = true;
      for (final key in fields.keys) {
        dynamic raw = value;
        for (final part in key.split('.')) {
          raw = raw is Map ? raw[part] : null;
        }
        controllers[key]!.text =
            raw is List ? raw.join('، ') : raw?.toString() ?? '';
      }
      final dob = DateTime.tryParse(controllers['dateOfBirth']!.text);
      if (dob != null)
        controllers['dateOfBirth']!.text =
            dob.toIso8601String().split('T').first;
      level = value['currentEducationLevel']?.toString() ?? '';
      if (!['', 'high-school', 'bachelor', 'master', 'phd'].contains(level))
        level = '';
    } catch (e) {
      if (mounted) error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final next = {
        ...profile,
        for (final entry in controllers.entries)
          if (!entry.key.contains('.')) entry.key: entry.value.text.trim()
      };
      next['targetCountries'] = controllers['targetCountries']!
          .text
          .split(RegExp('[,،]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      next['dateOfBirth'] = controllers['dateOfBirth']!.text.trim().isEmpty
          ? null
          : controllers['dateOfBirth']!.text.trim();
      next['currentEducationLevel'] = level;
      next['preferredFields'] = _list('preferredFields');
      next['englishTest'] = {
        'exam': controllers['englishTest.exam']!.text.trim(),
        'score': controllers['englishTest.score']!.text.trim(),
      };
      next['guardianContact'] = {
        'name': controllers['guardianContact.name']!.text.trim(),
        'relationship':
            controllers['guardianContact.relationship']!.text.trim(),
        'phone': controllers['guardianContact.phone']!.text.trim(),
        'email': controllers['guardianContact.email']!.text.trim(),
      };
      next['emergencyContact'] = {
        'name': controllers['emergencyContact.name']!.text.trim(),
        'relationship':
            controllers['emergencyContact.relationship']!.text.trim(),
        'phone': controllers['emergencyContact.phone']!.text.trim(),
      };
      double? number(String key) =>
          double.tryParse(controllers[key]!.text.trim());
      next['studyBudget'] = {
        'min': number('studyBudget.min'),
        'max': number('studyBudget.max'),
        'currency':
            controllers['studyBudget.currency']!.text.trim().toUpperCase(),
      };
      await StudentRepository.instance.updateProfile(next);
      if (!mounted) return;
      if (widget.onSaved != null) {
        widget.onSaved!();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  List<String> _list(String key) => controllers[key]!
      .text
      .split(RegExp('[,،]'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pickBirthDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final stored = DateTime.tryParse(controllers['dateOfBirth']!.text);
    final value = await showDatePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: today,
        initialDate:
            stored != null && !stored.isAfter(today) && stored.year >= 1900
                ? stored
                : DateTime(today.year - 18),
        helpText: 'تاريخ الميلاد',
        cancelText: 'إلغاء',
        confirmText: 'اختيار');
    if (value != null && mounted)
      setState(() => controllers['dateOfBirth']!.text =
          value.toIso8601String().split('T').first);
  }

  Widget field(String key) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: controllers[key],
        enabled: !saving,
        readOnly: key == 'dateOfBirth',
        onTap: key == 'dateOfBirth' ? pickBirthDate : null,
        textDirection: [
          'englishFullName',
          'passportNumber',
          'phone',
          'gpa',
          'englishTest.score',
          'studyBudget.min',
          'studyBudget.max',
          'dateOfBirth'
        ].contains(key)
            ? TextDirection.ltr
            : null,
        keyboardType: key.contains('phone')
            ? TextInputType.phone
            : ['gpa', 'englishTest.score', 'studyBudget.min', 'studyBudget.max']
                    .contains(key)
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
        minLines: key == 'bio' ? 3 : 1,
        maxLines: key == 'bio' ? 5 : 1,
        decoration: featureInput(fields[key]!,
            hint: key == 'targetCountries' ? 'مثال: تركيا، ألمانيا' : null,
            suffix: key == 'dateOfBirth'
                ? const Icon(Icons.calendar_today_outlined, size: 20)
                : null),
        validator: (value) {
          if (key != 'dateOfBirth' || value == null || value.trim().isEmpty)
            return null;
          final date = DateTime.tryParse(value.trim());
          return date == null || date.isAfter(DateTime.now())
              ? 'أدخل تاريخ ميلاد صحيحًا'
              : null;
        },
      ));

  @override
  Widget build(BuildContext context) => AppScaffold(
        title: 'الملف الشخصي',
        bottomBar: !loaded
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  color: Colors.white,
                  child: PrimaryButton(
                      label: saving ? 'جاري الحفظ...' : 'حفظ البيانات',
                      icon: Icons.check_rounded,
                      onPressed: saving ? null : save),
                )),
        body: loading
            ? const LoadingState()
            : error != null && !loaded
                ? ErrorState(message: error!, onRetry: load)
                : Form(
                    key: form,
                    child: FeatureBody(children: [
                      const FeatureIntro(
                          title: 'ملفك، بداية رحلتك',
                          subtitle:
                              'حدّث بياناتك لتسهيل التقديم ومتابعة طلباتك. يمكنك إكمالها في أي وقت.',
                          icon: Icons.person_outline_rounded),
                      if (error != null) InlineNotice(error!, error: true),
                      FeaturePanel(
                          title: 'المعلومات الشخصية',
                          subtitle: 'اكتب الاسم كما يظهر في وثائقك الرسمية.',
                          child: Column(children: [
                            field('englishFullName'),
                            field('phone'),
                            field('nationality'),
                            field('currentResidenceCountry'),
                            field('address'),
                          ])),
                      FeaturePanel(
                          title: 'وثائق الهوية',
                          child: Column(children: [
                            field('passportNumber'),
                            field('dateOfBirth')
                          ])),
                      FeaturePanel(
                          title: 'المعلومات الأكاديمية',
                          child: Column(children: [
                            DropdownButtonFormField<String>(
                                initialValue: level,
                                decoration: featureInput('المستوى الدراسي'),
                                items: const [
                                  DropdownMenuItem(
                                      value: '', child: Text('غير محدد')),
                                  DropdownMenuItem(
                                      value: 'high-school',
                                      child: Text('ثانوي')),
                                  DropdownMenuItem(
                                      value: 'bachelor',
                                      child: Text('بكالوريوس')),
                                  DropdownMenuItem(
                                      value: 'master', child: Text('ماجستير')),
                                  DropdownMenuItem(
                                      value: 'phd', child: Text('دكتوراه')),
                                ],
                                onChanged: saving
                                    ? null
                                    : (value) =>
                                        setState(() => level = value!)),
                            const SizedBox(height: 18),
                            field('currentEducation'),
                            field('gpa'),
                            field('englishTest.exam'),
                            field('englishTest.score'),
                          ])),
                      FeaturePanel(
                          title: 'خطتك الدراسية',
                          child: Column(children: [
                            field('targetCountries'),
                            field('preferredFields'),
                            field('preferredDegreeLevel'),
                            field('intake'),
                            field('studyBudget.min'),
                            field('studyBudget.max'),
                            field('studyBudget.currency'),
                            field('bio')
                          ])),
                      FeaturePanel(
                          title: 'بيانات ولي الأمر',
                          child: Column(children: [
                            field('guardianContact.name'),
                            field('guardianContact.relationship'),
                            field('guardianContact.phone'),
                            field('guardianContact.email'),
                          ])),
                      FeaturePanel(
                          title: 'جهة اتصال الطوارئ',
                          child: Column(children: [
                            field('emergencyContact.name'),
                            field('emergencyContact.relationship'),
                            field('emergencyContact.phone'),
                          ])),
                    ])),
      );
}
