import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/network/gateway_auth.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/features/settings/privacy_dialog.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// Desktop-parity gateway connect: base URL → probe → username/password.
///
/// No API_SERVER_KEY. Matches Desktop remote flow:
/// GET /api/status, GET /api/auth/providers, POST /auth/password-login,
/// then cookies + /api/auth/ws-ticket for the live socket.
///
/// [reauth] mode: session expired / kicked — keep gateway profile, re-prompt
/// credentials (no silent password re-login).
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({
    super.key,
    this.reauth = false,
    this.reauthMessage,
    this.existingProfile,
  });

  final bool reauth;
  final String? reauthMessage;
  final ConnectionProfile? existingProfile;

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  bool _obscure = true;
  bool _probed = false;
  String? _error;
  String? _hint;
  GatewayAuthProbe? _probe;
  String? _providerName;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingProfile;
    _urlCtrl = TextEditingController(
      text:
          existing?.baseUrl ??
          const String.fromEnvironment('HERMES_BASE_URL', defaultValue: ''),
    );
    _userCtrl = TextEditingController(text: existing?.username ?? '');
    _providerName = existing?.provider;
    if (widget.reauth) {
      _error = widget.reauthMessage ?? L10n.current.sessionExpiredBody;
      // Auto-probe so the password form is ready immediately.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_probeUrl());
      });
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _probeUrl() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _hint = null;
      _probed = false;
      _probe = null;
    });

    final baseUrl = _urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final probe = await GatewayAuthClient.probe(baseUrl);
      if (!mounted) return;
      if (!probe.reachable) {
        setState(() {
          _error = probe.error ?? L10n.current.gatewayNotReachable;
          _busy = false;
        });
        return;
      }

      final passwordProviders = probe.passwordProviders;
      setState(() {
        _probe = probe;
        _probed = true;
        _busy = false;
        _providerName = passwordProviders.isNotEmpty
            ? passwordProviders.first.name
            : (probe.providers.isNotEmpty ? probe.providers.first.name : null);
        if (probe.authMode == GatewayAuthMode.open) {
          _hint = L10n.current.gatewayOpenHint;
        } else if (probe.isPasswordGateway) {
          _hint = L10n.current.signInPasswordHint;
        } else if (probe.authMode == GatewayAuthMode.session &&
            passwordProviders.isEmpty) {
          _error = L10n.current.oauthOnlyError;
        }
      });

      // Open gateway: save immediately without password.
      if (probe.authMode == GatewayAuthMode.open) {
        await _saveOpen(probe);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _saveOpen(GatewayAuthProbe probe) async {
    final store = ref.read(connectionStoreProvider);
    await ref
        .read(connectionActionsProvider)
        .save(
          ConnectionProfile(
            id: store.newGatewayId(),
            baseUrl: probe.baseUrl,
            authMode: 'open',
            label: Uri.tryParse(probe.baseUrl)?.host,
            displayName: probe.version,
          ),
        );
    if (mounted) {
      setState(() => _hint = L10n.current.connectedOpenGateway);
    }
  }

  Future<void> _passwordLogin() async {
    final probe = _probe;
    if (probe == null) return;
    final provider = _providerName;
    if (provider == null || provider.isEmpty) {
      setState(() => _error = L10n.current.noPasswordProvider);
      return;
    }
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = L10n.current.usernamePasswordRequired);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final store = ref.read(connectionStoreProvider);
      // Reauth keeps the same gateway id (cookie jar path + pins).
      final gatewayId = widget.existingProfile?.id ?? store.newGatewayId();
      final jar = await GatewayAuthClient.persistentJar(gatewayId);
      await jar.deleteAll(); // start clean after expiry/kick
      final auth = GatewayAuthClient(baseUrl: probe.baseUrl, cookieJar: jar);

      await auth.passwordLogin(
        provider: provider,
        username: username,
        password: password,
      );

      // Prove session can mint a WS ticket (Desktop path).
      await auth.mintWsTicket();

      final existing = widget.existingProfile;
      await ref
          .read(connectionActionsProvider)
          .save(
            ConnectionProfile(
              id: gatewayId,
              baseUrl: probe.baseUrl,
              authMode: 'session',
              username: username,
              provider: provider,
              label: existing?.label ?? Uri.tryParse(probe.baseUrl)?.host,
              displayName: probe.version ?? existing?.displayName,
            ),
          );

      ref.read(connectionActionsProvider).clearReauth();
      // Bring WS back immediately after interactive sign-in.
      unawaited(ref.read(gatewayRealtimeProvider)?.ensureLive(force: true));

      if (mounted) {
        setState(() {
          _hint = L10n.current.signedInAs(username);
          _passCtrl.clear();
        });
      }
    } on GatewayAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.response?.data is Map
              ? '${(e.response!.data as Map)['detail'] ?? e.message}'
              : (e.message ?? e.toString());
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final probe = _probe;
    final passwordProviders = probe?.passwordProviders ?? const [];
    final showPasswordForm =
        _probed &&
        probe != null &&
        probe.authMode == GatewayAuthMode.session &&
        passwordProviders.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.reauth
                          ? context.l10n.signInAgain
                          : context.l10n.appTitle,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (!widget.reauth)
                      Text(
                        context.l10n.tagline,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.9,
                          ),
                          letterSpacing: -0.2,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      widget.reauth
                          ? context.l10n.sessionExpiredBanner
                          : context.l10n.connectIntro,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      container: true,
                      label: context.l10n.unofficialDisclaimer,
                      child: Text(
                        context.l10n.unofficialDisclaimer,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.68,
                          ),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _urlCtrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enabled: !_busy && !widget.reauth,
                      decoration: InputDecoration(
                        labelText: context.l10n.gatewayBaseUrl,
                        hintText: 'https://gateway.example.com',
                        helperText:
                            GatewayAuthClient.isUnencryptedPrivateNetworkUrl(
                              _urlCtrl.text,
                            )
                            ? context.l10n.httpPrivateNetworkHint
                            : null,
                        helperMaxLines: 2,
                      ),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return context.l10n.required;
                        return GatewayAuthClient.validateBaseUrl(t);
                      },
                      onChanged: (_) {
                        // Also forces a rebuild so the non-blocking HTTP
                        // helper text above updates as the user types.
                        setState(() {
                          if (_probed) {
                            _probed = false;
                            _probe = null;
                            _hint = null;
                            _error = null;
                          }
                        });
                      },
                    ),
                    if (showPasswordForm) ...[
                      const SizedBox(height: 16),
                      if (passwordProviders.length > 1)
                        DropdownButtonFormField<String>(
                          // ignore: deprecated_member_use
                          value: _providerName,
                          decoration: InputDecoration(
                            labelText: context.l10n.provider,
                          ),
                          items: [
                            for (final p in passwordProviders)
                              DropdownMenuItem(
                                value: p.name,
                                child: Text(p.displayName),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _providerName = v),
                        ),
                      if (passwordProviders.length > 1)
                        const SizedBox(height: 12),
                      TextFormField(
                        controller: _userCtrl,
                        autocorrect: false,
                        enabled: !_busy,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: InputDecoration(
                          labelText: context.l10n.username,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        enabled: !_busy,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _passwordLogin(),
                        decoration: InputDecoration(
                          labelText: context.l10n.password,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    if (_hint != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _hint!,
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : (showPasswordForm ? _passwordLogin : _probeUrl),
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              showPasswordForm
                                  ? context.l10n.signIn
                                  : context.l10n.continueAction,
                            ),
                    ),
                    if (showPasswordForm) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _probed = false;
                                _probe = null;
                                _error = null;
                                _hint = null;
                              }),
                        child: Text(context.l10n.changeUrl),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => showPrivacyDialog(context),
                      icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                      label: Text(context.l10n.privacyAndData),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
