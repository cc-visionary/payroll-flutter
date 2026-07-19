import '../../data/models/workforce_planning.dart';

/// Load band for a person. Over = >100%, OK = 80–100% inclusive, Under = <80%.
enum LoadStatus { under, ok, over }

/// Monthly hours at [multiplier]: fixed work is constant, growing work scales.
double projectedHours(double hoursFixed, double hoursGrowingBase, double multiplier) =>
    hoursFixed + hoursGrowingBase * multiplier;

/// Load as a fraction of capacity; 0 when capacity is unknown/zero.
double loadFraction(double hours, double capacityHours) =>
    capacityHours <= 0 ? 0 : hours / capacityHours;

/// A person's load fraction. Uses the person's stored [WpPersonLoad.growthMultiplier]
/// unless [multiplier] is supplied (live slider preview).
double personLoad(WpPersonLoad p, {double? multiplier}) => loadFraction(
    projectedHours(p.hoursFixed, p.hoursGrowingBase, multiplier ?? p.growthMultiplier),
    p.capacityHours);

LoadStatus loadStatus(double fraction) {
  if (fraction > 1.0) return LoadStatus.over;
  if (fraction >= 0.8) return LoadStatus.ok;
  return LoadStatus.under;
}
