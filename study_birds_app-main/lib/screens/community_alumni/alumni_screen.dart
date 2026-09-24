import 'package:flutter/material.dart';
import '../../core/student_repository.dart';
import '../../core/app_theme.dart';

class AlumniScreen extends StatefulWidget {
  const AlumniScreen({super.key});

  @override
  State<AlumniScreen> createState() => _AlumniScreenState();
}

class _AlumniScreenState extends State<AlumniScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loadingList = true;
  bool _loadingProfile = true;
  List<dynamic> _alumni = [];
  final _fieldFilter = TextEditingController();
  final _countryFilter = TextEditingController();

  // Profile edit fields
  final _bioCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _employerCtrl = TextEditingController();
  final _linkedInCtrl = TextEditingController();
  bool _isPublic = true;
  bool _savingProfile = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadAlumni();
    _loadMyProfile();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _fieldFilter.dispose();
    _countryFilter.dispose();
    _bioCtrl.dispose();
    _positionCtrl.dispose();
    _employerCtrl.dispose();
    _linkedInCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAlumni() async {
    try {
      final data = await StudentRepository.instance.listAlumni();
      if (mounted) setState(() => _alumni = data);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _loadMyProfile() async {
    try {
      final p = await StudentRepository.instance.getMyAlumniProfile();
      if (mounted && p != null) {
        setState(() {
          _bioCtrl.text = p['bio'] ?? '';
          _positionCtrl.text = p['currentPosition'] ?? '';
          _employerCtrl.text = p['employer'] ?? '';
          _linkedInCtrl.text = p['linkedInUrl'] ?? '';
          _isPublic = p['isPublic'] ?? true;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _savingProfile = true);
    try {
      await StudentRepository.instance.upsertMyAlumniProfile({
        'bio': _bioCtrl.text.trim(),
        'currentPosition': _positionCtrl.text.trim(),
        'employer': _employerCtrl.text.trim(),
        'linkedInUrl': _linkedInCtrl.text.trim(),
        'isPublic': _isPublic,
      });
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الملف')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'شبكة الخريجين',
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            tabs: const [Tab(text: 'استعرض الخريجين'), Tab(text: 'ملفي')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_buildBrowseTab(), _buildProfileTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowseTab() {
    if (_loadingList) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadAlumni,
      child: _alumni.isEmpty
          ? const Center(child: Text('لا يوجد خريجون متاحون بعد'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _alumni.length,
              itemBuilder: (_, i) {
                final a = _alumni[i] as Map<String, dynamic>;
                final name = a['name'] ?? '';
                final position = a['currentPosition'] ?? '';
                final employer = a['employer'] ?? '';
                final country = a['currentCountry'] ?? '';
                final verified = a['isVerified'] == true;
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.navy,
                      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white)),
                    ),
                    title: Row(children: [
                      Text(name, style: AppTextStyles.cardTitle),
                      if (verified) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified, color: AppColors.navy, size: 16),
                      ],
                    ]),
                    subtitle: Text([position, employer, country]
                        .where((s) => s.isNotEmpty)
                        .join(' · ')),
                    trailing: a['linkedInUrl'] != null && (a['linkedInUrl'] as String).isNotEmpty
                        ? Icon(Icons.link, color: AppColors.navy)
                        : null,
                  ),
                );
              },
            ),
    );
  }

  Widget _buildProfileTab() {
    if (_loadingProfile) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ملفي الشخصي كخريج', style: AppTextStyles.sectionLabel),
              const SizedBox(height: 12),
              _field('نبذة', _bioCtrl, maxLines: 3),
              _field('المنصب الحالي', _positionCtrl),
              _field('جهة العمل', _employerCtrl),
              _field('رابط LinkedIn', _linkedInCtrl),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إظهار ملفي للآخرين'),
                value: _isPublic,
                onChanged: (v) => setState(() => _isPublic = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _savingProfile
                    ? const Center(child: CircularProgressIndicator())
                    : PrimaryButton(
                        label: 'حفظ الملف',
                        onPressed: _saveProfile,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          ),
        ],
      ),
    );
  }
}
