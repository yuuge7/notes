/// The eight note colours.
///
/// A pigment names a colour role, not a colour value: the theme resolves it to
/// a spine colour and a card tint per brightness. `graphite` means "no colour"
/// and renders as a plain paper card with no spine.
enum Pigment {
  graphite('None'),
  vermilion('Vermilion'),
  amber('Amber'),
  moss('Moss'),
  verdigris('Verdigris'),
  indigo('Indigo'),
  plum('Plum'),
  clay('Clay');

  Pigment(this.label);

  /// Human-readable name, used in the picker and in accessibility labels.
  final String label;

  bool get isNone => this == Pigment.graphite;
}
