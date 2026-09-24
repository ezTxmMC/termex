enum DefaultView { local, ssh }
enum TerminalType { zsh, bash, fish }

class AppSettings {
  final DefaultView defaultView;
  final TerminalType terminalType;
  final bool rememberLastTab;

  AppSettings({
    this.defaultView = DefaultView.local,
    this.terminalType = TerminalType.zsh,
    this.rememberLastTab = true,
  });

  AppSettings copyWith({
    DefaultView? defaultView,
    TerminalType? terminalType,
    bool? rememberLastTab,
  }) =>
      AppSettings(
        defaultView: defaultView ?? this.defaultView,
        terminalType: terminalType ?? this.terminalType,
        rememberLastTab: rememberLastTab ?? this.rememberLastTab,
      );

  Map<String, dynamic> toJson() => {
    'defaultView': defaultView.name,
    'terminalType': terminalType.name,
    'rememberLastTab': rememberLastTab,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      defaultView: DefaultView.values
          .firstWhere((e) => e.name == json['defaultView'], orElse: () => DefaultView.local),
      terminalType: TerminalType.values
          .firstWhere((e) => e.name == json['terminalType'], orElse: () => TerminalType.zsh),
      rememberLastTab: json['rememberLastTab'] as bool? ?? true,
    );
  }
}
