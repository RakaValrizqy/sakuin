# Catatan Rilis Sakuin

## v1.1.0
### Apa yang Baru
- **Logo & Ikon Sakuin Baru:** Ikon dompet/saku modern bertema emerald-teal dengan dukungan Adaptive Icon & Material You.
- **Pembagian Budget di Dalam Saku (Pos Saku):** Kini satu saku (mis. Mandiri Rp 500.000) bisa dibagi menjadi beberapa pos budget (mis. Uang Harian Rp 200.000 & Tabungan Rp 300.000) lengkap dengan Saldo Bebas, progress target, alokasi manual, transfer antar budget di saku yang sama, transfer lintas saku langsung ke pos tertentu, serta pencatatan transaksi per pos.
- **Pembaruan Otomatis dari Aplikasi:** Sakuin otomatis mengecek rilis terbaru dari GitHub Releases, menampilkan rangkuman perubahan, mengunduh APK sesuai perangkat (`arm64-v8a`), dan membuka pemasang Android langsung dari aplikasi tanpa uninstall.

### Peningkatan & Migrasi
- Migrasi database non-destruktif (`v1 → v2`) agar seluruh data lama tetap utuh saat update.
- Backup & Restore `.json` diperbarui ke format v2 untuk ikut menyimpan pos budget & riwayat alokasi (tetap kompatibel dengan cadangan v1).

## v1.0.0
- Rilis perdana Sakuin: Saku/Dompet, Input Cepat (Item Memory, Item Cepat, Keypad kustom `k`/`jt`/kalkulator), Transaksi Berulang, Hutang-Piutang dua arah, Laporan & grafik `CustomPainter`, Anggaran bulanan, ekspor CSV/PDF, PIN + Biometrik, dan Backup/Restore SAF.
