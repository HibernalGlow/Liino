import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A settings group that opens and closes when its header is clicked.
/// Whether it is open is remembered per [id] for as long as the app runs,
/// so leaving the settings page and coming back keeps the layout.
class CollapsibleSettingsSection extends StatefulWidget {
  final String id;
  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  /// Wraps the section in the caller's card (the settings page passes its
  /// blur-aware one). Defaults to a plain rounded panel.
  final Widget Function(Widget child)? cardBuilder;

  const CollapsibleSettingsSection({
    super.key,
    required this.id,
    required this.title,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
    this.cardBuilder,
  });

  static final Map<String, bool> _remembered = {};

  @visibleForTesting
  static void resetRememberedState() => _remembered.clear();

  @override
  State<CollapsibleSettingsSection> createState() =>
      _CollapsibleSettingsSectionState();
}

class _CollapsibleSettingsSectionState
    extends State<CollapsibleSettingsSection> {
  late bool _expanded =
      CollapsibleSettingsSection._remembered[widget.id] ??
      widget.initiallyExpanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    CollapsibleSettingsSection._remembered[widget.id] = _expanded;
  }

  @override
  Widget build(BuildContext context) {
    final content = Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(widget.icon, size: 18, color: Colors.white70),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      LucideIcons.chevronDown,
                      size: 18,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    children: [
                      const Divider(height: 1, color: Colors.white10),
                      ...widget.children,
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );

    final card =
        widget.cardBuilder?.call(content) ??
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: content,
        );
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: card);
  }
}
