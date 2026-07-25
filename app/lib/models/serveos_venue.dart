/// A bejelentkezett TaskMail user ServeOS `venue_users` sora alapján — ez a
/// meglévő híd (lásd `serveos_admin/supabase/migration.sql`), amit a
/// venue-választó a "Küldés ServeOS-be" művelethez használ.
class ServeosVenue {
  final String venueId;
  final String name;
  final String role;

  const ServeosVenue({required this.venueId, required this.name, required this.role});

  factory ServeosVenue.fromJson(Map<String, dynamic> json) => ServeosVenue(
        venueId: json['venue_id'] as String,
        name: (json['venues'] as Map<String, dynamic>?)?['name'] as String? ?? 'Ismeretlen venue',
        role: json['role'] as String? ?? '',
      );
}
