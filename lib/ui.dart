import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Small building blocks mirroring Lumen IDE's `components/ui`.

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

void toast(String message) => messengerKey.currentState
  ?..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

enum BtnVariant { ghost, solid, outline, danger }

/// Lumen `Button`: 24/28 px high, 6 px radius, ghost by default.
class Btn extends StatefulWidget {
  final Widget? icon;
  final String? label;
  final VoidCallback? onTap;
  final BtnVariant variant;
  final bool small;
  final bool active;
  final String? tooltip;

  const Btn({
    super.key,
    this.icon,
    this.label,
    this.onTap,
    this.variant = BtnVariant.ghost,
    this.small = false,
    this.active = false,
    this.tooltip,
  });

  @override
  State<Btn> createState() => _BtnState();
}

class _BtnState extends State<Btn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final (Color? bg, Color fg, Color? border) = switch (widget.variant) {
      BtnVariant.ghost => (
        _hover ? L.hover : null,
        widget.active ? L.accent : (_hover ? L.text : L.muted),
        null,
      ),
      BtnVariant.solid => (
        _hover ? L.accent.withValues(alpha: .9) : L.accent,
        L.onAccent,
        null,
      ),
      BtnVariant.outline => (
        _hover ? L.hover : null,
        L.text,
        _hover ? L.borderStrong : L.border,
      ),
      BtnVariant.danger => (
        _hover ? L.danger.withValues(alpha: .12) : null,
        L.danger,
        null,
      ),
    };
    final h = widget.small ? 24.0 : 28.0;
    Widget child = Container(
      height: h,
      constraints: BoxConstraints(minWidth: h),
      padding: EdgeInsets.symmetric(
        horizontal: widget.label == null ? 0 : (widget.small ? 8 : 10),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(L.radiusSm),
        border: border == null ? null : Border.all(color: border),
      ),
      alignment: Alignment.center,
      child: IconTheme(
        data: IconThemeData(color: fg, size: widget.small ? 14 : 15),
        child: DefaultTextStyle(
          style: TextStyle(
            color: fg,
            fontSize: widget.small ? 11.5 : 12.5,
            fontWeight: FontWeight.w500,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) widget.icon!,
              if (widget.icon != null && widget.label != null)
                const SizedBox(width: 6),
              if (widget.label != null) Text(widget.label!),
            ],
          ),
        ),
      ),
    );
    child = Opacity(opacity: enabled ? 1 : .4, child: child);
    child = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: child),
    );
    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}

/// Uppercase section caption (`text-[10.5px] tracking-[0.09em] text-subtle`).
class Caption extends StatelessWidget {
  final String text;
  const Caption(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 1,
      color: L.subtle,
    ),
  );
}

/// Centered empty state with icon, title and hint.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: L.subtle.withValues(alpha: .6)),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: L.muted),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                color: L.subtle,
                height: 1.5,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}

/// Hoverable row used in lists (hosts, files, menus).
class HoverRow extends StatefulWidget {
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(Offset)? onContextMenu;
  final EdgeInsets padding;
  final double radius;

  const HoverRow({
    super.key,
    required this.child,
    this.selected = false,
    this.onTap,
    this.onDoubleTap,
    this.onContextMenu,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    this.radius = L.radiusSm,
  });

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  bool _hover = false;
  DateTime _lastDown = DateTime(0);

  // Reacts on pointer down without waiting for gesture arenas: a
  // GestureDetector with onDoubleTap holds back every single click ~300 ms.
  void _down(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    final now = DateTime.now();
    final isDouble =
        widget.onDoubleTap != null &&
        now.difference(_lastDown) < const Duration(milliseconds: 400);
    _lastDown = isDouble ? DateTime(0) : now;
    isDouble ? widget.onDoubleTap!() : widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: widget.onContextMenu == null
            ? null
            : (d) => widget.onContextMenu!(d.globalPosition),
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.selected
                ? L.active
                : (_hover ? L.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          child: widget.child,
        ),
      ),
    ),
  );
}

/// An entry of a context menu. `null` in the list renders a separator.
class MenuEntry {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? hint;
  final bool danger;
  const MenuEntry(
    this.label,
    this.onTap, {
    this.icon,
    this.hint,
    this.danger = false,
  });
}

/// Lumen-style popup menu at [position].
Future<void> showContextMenu(
  BuildContext context,
  Offset position,
  List<MenuEntry?> entries,
) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final picked = await showMenu<MenuEntry>(
    context: context,
    popUpAnimationStyle: AnimationStyle.noAnimation,
    color: L.overlay,
    elevation: 8,
    shadowColor: Colors.black54,
    menuPadding: const EdgeInsets.all(4),
    constraints: const BoxConstraints(minWidth: 210, maxWidth: 440),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(L.radius),
      side: const BorderSide(color: L.border),
    ),
    // The overlay may be scaled (UI zoom), so map screen → overlay space.
    position: RelativeRect.fromRect(
      overlay.globalToLocal(position) & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      for (final e in entries)
        if (e == null)
          const _MenuSeparator()
        else
          PopupMenuItem<MenuEntry>(
            value: e,
            enabled: e.onTap != null,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: e.icon == null
                      ? null
                      : Icon(
                          e.icon,
                          size: 14,
                          color: e.danger ? L.danger : L.muted,
                        ),
                ),
                Expanded(
                  child: Text(
                    e.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: e.danger ? L.danger : L.text,
                    ),
                  ),
                ),
                if (e.hint != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      e.hint!,
                      style: const TextStyle(fontSize: 10.5, color: L.subtle),
                    ),
                  ),
              ],
            ),
          ),
    ],
  );
  picked?.onTap?.call();
}

class _MenuSeparator extends PopupMenuEntry<MenuEntry> {
  const _MenuSeparator();

  @override
  double get height => 9;

  @override
  bool represents(MenuEntry? value) => false;

  @override
  State<_MenuSeparator> createState() => _MenuSeparatorState();
}

class _MenuSeparatorState extends State<_MenuSeparator> {
  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 4),
    color: L.border,
  );
}

/// Dialog frame like Lumen's modals: title row, body, footer buttons.
class LDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;
  const LDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = 440,
  });

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: L.overlay,
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.only(left: 16, right: 6),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: L.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Btn(
                  small: true,
                  icon: const Icon(Icons.close),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
          if (actions.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: L.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final a in actions) ...[const SizedBox(width: 6), a],
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// Labeled text field with Lumen spacing.
class Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final int lines;
  final bool mono;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  const Field(
    this.controller,
    this.label, {
    super.key,
    this.hint,
    this.obscure = false,
    this.lines = 1,
    this.mono = false,
    this.autofocus = false,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: L.muted),
          ),
        ),
        TextField(
          controller: controller,
          obscureText: obscure,
          minLines: lines,
          maxLines: lines,
          autofocus: autofocus,
          onSubmitted: onSubmitted,
          style: TextStyle(fontSize: 12.5, fontFamily: mono ? L.mono : null),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: L.subtle, fontSize: 12.5),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 9,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Asks for a single line of text.
Future<String?> prompt(
  String title, {
  String label = '',
  String initial = '',
  bool obscure = false,
  String ok = 'OK',
}) {
  final c = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    animationStyle: AnimationStyle.noAnimation,
    context: navigatorKey.currentContext!,
    builder: (ctx) => LDialog(
      title: title,
      width: 400,
      actions: [
        Btn(label: 'Cancel', onTap: () => Navigator.pop(ctx)),
        Btn(
          label: ok,
          variant: BtnVariant.solid,
          onTap: () => Navigator.pop(ctx, c.text),
        ),
      ],
      child: Field(
        c,
        label,
        obscure: obscure,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
    ),
  );
}

Future<bool> confirm(
  String title,
  String message, {
  String ok = 'OK',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    animationStyle: AnimationStyle.noAnimation,
    context: navigatorKey.currentContext!,
    builder: (ctx) => LDialog(
      title: title,
      width: 420,
      actions: [
        Btn(label: 'Cancel', onTap: () => Navigator.pop(ctx, false)),
        Btn(
          label: ok,
          variant: danger ? BtnVariant.danger : BtnVariant.solid,
          onTap: () => Navigator.pop(ctx, true),
        ),
      ],
      child: SelectableText(
        message,
        style: const TextStyle(fontSize: 12.5, color: L.muted, height: 1.5),
      ),
    ),
  );
  return r ?? false;
}

String formatBytes(num b) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  var v = b.toDouble();
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return i == 0 ? '${v.toInt()} B' : '${v.toStringAsFixed(1)} ${units[i]}';
}

/// App-wide shortcuts. Also consulted by terminals, which would otherwise
/// swallow every key press.
final Map<SingleActivator, VoidCallback> appShortcuts = {};

KeyEventResult handleAppShortcut(KeyEvent e) {
  if (e is! KeyDownEvent) return KeyEventResult.ignored;
  for (final s in appShortcuts.entries) {
    if (s.key.accepts(e, HardwareKeyboard.instance)) {
      s.value();
      return KeyEventResult.handled;
    }
  }
  return KeyEventResult.ignored;
}
