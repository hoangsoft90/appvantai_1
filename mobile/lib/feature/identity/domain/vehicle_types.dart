/// Loại xe cho phép — phải khớp worker/src/services/profiles.ts (VEHICLE_TYPES).
const vehicleTypeLabels = <String, String>{
  'van': 'Xe van',
  'pickup': 'Xe bán tải',
  'truck': 'Xe tải',
  'container': 'Xe container',
};

String vehicleTypeLabel(String type) => vehicleTypeLabels[type] ?? type;