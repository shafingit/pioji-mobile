import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_icons.dart';
import '../../../core/design/context_ext.dart';
import '../../../core/design/typography.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/detail.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/form_submit.dart';
import '../../../core/widgets/module_list.dart';
import '../../../core/widgets/scaffolds.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/user.dart';
import '../../masters/data/masters_repository.dart';
import '../data/users_repository.dart';

String _roleName(User u, List<Role> roles) {
  for (final r in roles) {
    if (r.slug == u.role) return r.name;
  }
  return u.roleText ?? u.role ?? 'No role';
}

/// Everyone who can sign in to the app, for super admins.
class UsersListScreen extends ConsumerWidget {
  const UsersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(rolesProvider).value ?? const <Role>[];
    final canCreate = ref.watch(currentUserProvider)?.can('users.create') ?? true;
    return ModuleListScreen<User>(
      title: 'Users',
      inTabs: false,
      listProvider: usersListProvider,
      queryProvider: usersQueryProvider,
      searchHint: 'Search name, email or phone',
      emptyIcon: AppIcons.people,
      emptyTitle: 'No users yet',
      emptyBody: 'People who can sign in to Pioji show up here.',
      newLabel: canCreate ? 'Add user' : null,
      onNew: canCreate ? () => context.pushNamed(Routes.userNew) : null,
      actions: [if (canCreate) AddButton(semanticLabel: 'Add user', onPressed: () => context.pushNamed(Routes.userNew))],
      segments: const SegmentConfig(param: 'status', options: {'': 'All', 'active': 'Active', 'inactive': 'Inactive'}),
      filters: [ChoiceFilter('role', 'Role', {for (final r in roles) r.slug: r.name})],
      itemBuilder: (context, u) => AppListRow(
        leading: IconTile(initial: u.initial, size: 34),
        title: u.name,
        subtitle: [_roleName(u, roles), if (u.phone != null) u.phone!, u.email].join(' · '),
        onTap: () => context.pushNamed(Routes.userDetail, pathParameters: {'id': '${u.id}'}, extra: u),
        trailing: u.status == 'inactive' ? const StatusBadge('Inactive', tone: Tone.neutral) : null,
      ),
    );
  }
}

/// One user: contact, role, linked buyers; change role, activate or deactivate.
class UserDetailScreen extends ConsumerStatefulWidget {
  const UserDetailScreen({super.key, required this.user});
  final User? user;

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen> {
  late User? _u = widget.user;
  bool _busy = false;

  Future<void> _reload() async {
    final id = _u?.id;
    if (id == null) return;
    final fresh = await ref.read(usersRepositoryProvider).get(id);
    if (mounted) setState(() => _u = fresh);
    ref.invalidate(usersListProvider);
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
      if (mounted) context.toast(done);
    } catch (_) {
      if (mounted) context.toast("Couldn't update the user. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeRole(User u, List<Role> roles) async {
    final picked = await showPickerSheet<String>(
      context,
      title: 'Role for ${u.name}',
      selected: u.role,
      options: [for (final r in roles) PickOption(r.slug, r.name, subtitle: r.description)],
    );
    if (picked == null || picked == u.role || !mounted) return;
    await _run(() => ref.read(usersRepositoryProvider).setRole(u.id!, picked), 'Role changed');
  }

  Future<void> _toggleStatus(User u) async {
    final active = u.status != 'inactive';
    final ok = await confirm(
      context,
      title: active ? 'Deactivate ${u.name}?' : 'Activate ${u.name}?',
      body: active ? "They won't be able to sign in until they're activated again." : 'They can sign in again.',
      action: active ? 'Deactivate' : 'Activate',
      destructive: active,
    );
    if (!ok || !mounted) return;
    await _run(() => ref.read(usersRepositoryProvider).setStatus(u.id!, active: !active), active ? 'User deactivated' : 'User activated');
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    if (u == null) return const MissingItemScreen(what: 'user');
    final c = context.colors;
    final me = ref.watch(currentUserProvider);
    final roles = ref.watch(rolesProvider).value ?? const <Role>[];
    final buyers = ref.watch(buyersProvider).value ?? const <MasterItem>[];
    final linked = [
      for (final id in u.buyerIds) buyers.where((b) => b.id == id).map((b) => b.name).firstOrNull ?? 'Buyer #$id',
    ];
    final canEdit = me?.can('users.edit') ?? true;
    final isMe = me?.id != null && me!.id == u.id;
    return DetailScaffold(
      title: u.name,
      actions: [
        if (canEdit) LinkButton(label: 'Edit', onPressed: () => context.pushNamed(Routes.userEdit, pathParameters: {'id': '${u.id}'}, extra: u)),
      ],
      children: [
        GroupedSection(
          children: [
            InfoRow('Email', u.email),
            InfoRow('Phone', u.phone ?? 'Not set'),
            InfoRow('Department', u.department ?? 'Not set'),
            InfoRow('Status', u.status == 'inactive' ? 'Inactive' : 'Active', valueColor: u.status == 'inactive' ? c.warning : null),
          ],
        ),
        GroupedSection(
          label: 'Access',
          footer: Text(u.permissions == null ? '' : '${u.permissions!.length} permissions from this role.'),
          children: [
            AppListRow(
              title: 'Role',
              titleStyle: AppText.body,
              minHeight: 48,
              trailing: Text(_roleName(u, roles), style: AppText.body.copyWith(color: c.textSecondary)),
              showChevron: canEdit && !isMe && roles.isNotEmpty,
              onTap: canEdit && !isMe && roles.isNotEmpty && !_busy ? () => _changeRole(u, roles) : null,
            ),
            InfoRow('Linked buyers', linked.isEmpty ? 'None' : linked.join(', ')),
          ],
        ),
        if (canEdit && !isMe)
          PrimaryButton(
            label: u.status == 'inactive' ? 'Activate user' : 'Deactivate user',
            destructive: u.status != 'inactive',
            loading: _busy,
            onPressed: () => _toggleStatus(u),
          ),
      ],
    );
  }
}

/// Add or edit a user. A new user needs a password; on edit it's optional
/// and only sent when typed.
class UserFormScreen extends ConsumerStatefulWidget {
  const UserFormScreen({super.key, this.editing});
  final User? editing;

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> with FormSubmit {
  late final User? _e = widget.editing;
  late final _name = TextEditingController(text: _e?.name);
  late final _email = TextEditingController(text: _e?.email);
  late final _phone = TextEditingController(text: _e?.phone);
  late final _department = TextEditingController(text: _e?.department);
  final _password = TextEditingController();
  late String? _role = _e?.role;
  late Set<int> _buyerIds = {...?_e?.buyerIds};

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _department, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(usersRepositoryProvider);
    final body = <String, Object?>{
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'department': _department.text.trim(),
      'role': _role,
      'password': _password.text,
      'buyer_ids': _buyerIds.toList(),
    };
    final ok = await submit<bool>(
      () async {
        _e == null ? await repo.create(body) : await repo.update(_e.id!, body);
        return true;
      },
      clientErrors: {
        if (_name.text.trim().isEmpty) 'name': 'Enter a name.',
        if (!_email.text.contains('@')) 'email': 'Enter an email address.',
        if (_role == null) 'role': 'Choose a role.',
        if (_e == null && _password.text.length < 8) 'password': 'Use at least 8 characters.',
      },
    );
    if (ok == true && mounted) {
      ref.invalidate(usersListProvider);
      context.toast(_e == null ? 'User added' : 'User updated');
      context.goNamed(Routes.users);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(rolesProvider).value ?? const <Role>[];
    final buyers = ref.watch(buyersProvider).value ?? const <MasterItem>[];
    String? roleName;
    for (final r in roles) {
      if (r.slug == _role) roleName = r.name;
    }
    return FormScaffold(
      title: _e == null ? 'Add user' : 'Edit user',
      submitLabel: _e == null ? 'Add user' : 'Save changes',
      submitting: submitting,
      onSubmit: _save,
      children: [
        if (banner != null) FormBanner(banner!),
        GroupedSection(
          children: [
            FieldInput(label: 'Name', hint: 'Anita Das', controller: _name, error: err('name'), textCapitalization: TextCapitalization.words),
            FieldInput(label: 'Email', hint: 'name@company.com', controller: _email, error: err('email'), keyboardType: TextInputType.emailAddress),
            FieldInput(label: 'Phone', hint: '98765 43210', controller: _phone, error: err('phone'), keyboardType: TextInputType.phone),
            FieldInput(label: 'Department', hint: 'Tasting', controller: _department, error: err('department')),
          ],
        ),
        GroupedSection(
          label: 'Access',
          children: [
            ValueRow(
              label: 'Role',
              value: roleName ?? _role,
              error: err('role'),
              onTap: () async {
                final list = await ref.read(rolesProvider.future);
                if (!context.mounted) return;
                final picked = await showPickerSheet<String>(
                  context,
                  title: 'Role',
                  selected: _role,
                  options: [for (final r in list) PickOption(r.slug, r.name, subtitle: r.description)],
                );
                if (picked != null) setState(() => _role = picked);
              },
            ),
            ValueRow(
              label: 'Linked buyers',
              value: _buyerIds.isEmpty ? null : '${_buyerIds.length} selected',
              placeholder: 'None',
              onTap: () async {
                final list = await ref.read(buyersProvider.future);
                if (!context.mounted) return;
                final sel = await showMultiPickerSheet<int>(
                  context,
                  title: 'Linked buyers',
                  selected: _buyerIds,
                  options: [for (final b in list) PickOption(b.id, b.name, subtitle: b.subtitle)],
                );
                if (sel != null) setState(() => _buyerIds = sel);
              },
            ),
            if (buyers.isEmpty && _buyerIds.isNotEmpty) InfoRow('Buyer ids', _buyerIds.join(', ')),
          ],
        ),
        GroupedSection(
          footer: Text(_e == null ? 'At least 8 characters. Share it with the user securely.' : 'Leave empty to keep the current password.'),
          children: [
            FieldInput(label: _e == null ? 'Password' : 'New password', controller: _password, obscureText: true, error: err('password')),
          ],
        ),
      ],
    );
  }
}
