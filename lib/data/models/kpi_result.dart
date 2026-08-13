/// The three levels a KPI result can be computed at.
enum KpiScope { personal, department, company }

/// A period's verdict on one KPI.
///
/// [noData] is NOT a soft failure — it means the engine could not form a
/// judgement, and it must never render as red. Red means data existed and the
/// target was missed. Conflating them trains people to ignore red.
enum KpiStatus { onTrack, offTrack, noData }

const kpiScopeCodes = {
  KpiScope.personal: 'PERSONAL',
  KpiScope.department: 'DEPARTMENT',
  KpiScope.company: 'COMPANY',
};

const kpiStatusCodes = {
  KpiStatus.onTrack: 'ON_TRACK',
  KpiStatus.offTrack: 'OFF_TRACK',
  KpiStatus.noData: 'NO_DATA',
};
