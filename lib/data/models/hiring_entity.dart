class HiringEntity {
  final String id;
  final String companyId;
  final String code;
  final String name;
  final String? tradeName;
  final String? tin;
  final String? rdoCode;
  final String? sssEmployerId;
  final String? philhealthEmployerId;
  final String? pagibigEmployerId;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? province;
  final String? zipCode;
  final String country;
  final String? phoneNumber;
  final String? email;
  final bool isActive;

  const HiringEntity({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    this.tradeName,
    this.tin,
    this.rdoCode,
    this.sssEmployerId,
    this.philhealthEmployerId,
    this.pagibigEmployerId,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.province,
    this.zipCode,
    this.country = 'PH',
    this.phoneNumber,
    this.email,
    this.isActive = true,
  });

  factory HiringEntity.fromRow(Map<String, dynamic> r) => HiringEntity(
        id: r['id'] as String,
        companyId: r['company_id'] as String,
        code: r['code'] as String,
        name: r['name'] as String,
        tradeName: r['trade_name'] as String?,
        tin: r['tin'] as String?,
        rdoCode: r['rdo_code'] as String?,
        sssEmployerId: r['sss_employer_id'] as String?,
        philhealthEmployerId: r['philhealth_employer_id'] as String?,
        pagibigEmployerId: r['pagibig_employer_id'] as String?,
        addressLine1: r['address_line1'] as String?,
        addressLine2: r['address_line2'] as String?,
        city: r['city'] as String?,
        province: r['province'] as String?,
        zipCode: r['zip_code'] as String?,
        country: r['country'] as String? ?? 'PH',
        phoneNumber: r['phone_number'] as String?,
        email: r['email'] as String?,
        isActive: r['is_active'] as bool? ?? true,
      );
}
