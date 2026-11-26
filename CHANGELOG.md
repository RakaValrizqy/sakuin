# Catatan Rilis Sakuin

## v1.3.0
### Apa yang Baru
- **Dompet & Hutang di Menu Utama (Navbar):** Dompet dan Hutang-Piutang kini bisa langsung diakses dari bilah navigasi bawah (Beranda, Transaksi, Dompet, Hutang, Lainnya), sedangkan Laporan & Grafik tersedia di ikon atas Beranda dan tab Lainnya.
- **Input Nominal Lebih Nyaman:** Semua kolom nominal kini langsung membuka **keyboard angka (numpad)** dan otomatis memformat **titik pemisah ribuan** saat mengetik (mis. `300000` → `Rp 300.000`).
- **UX Alokasi Pos Budget Baru:** Layar **Atur Semua Alokasi** pada detail saku dengan tampilan total saldo vs saldo bebas secara *real-time*, grafik batang proporsi pos, slider interaktif, tombol cepat (`+50 rb`, `+100 rb`, `Isi sisa`, `Bagi rata`, `0`), serta tombol cepat buat pos preset 1 ketukan.
- **Tampilan Versi Aplikasi:** Nomor versi & build terpasang kini tampil jelas di menu **Lainnya** dan **Pengaturan → Pembaruan Aplikasi**.
- **Dukungan Auto-Update Repo Private:** Menambahkan opsi **Token GitHub (opsional)** terenkripsi di Pengaturan agar auto-update tetap berjalan lancar meski repositori GitHub bersifat *Private*, disertai pesan error HTTP 404 yang informatif.

## v1.2.0
### Apa yang Baru
- **Auto Catat Pengeluaran dari Email QRIS (Gmail):** Hubungkan Gmail memakai App Password (16 huruf, tanpa setup Google Cloud Console & tidak perlu login ulang tiap 7 hari). Sakuin membaca email QRIS dari Mandiri/Livin', BCA, BRI, BNI, BSI, GoPay, OVO, DANA, ShopeePay, SeaBank, Jago, dll. dalam mode *read-only* lalu memasukkannya ke **Antrean Review QRIS** (tersedia juga opsi langsung simpan otomatis).
- **Pecah Transaksi (Split Komponen):** Dari satu transaksi (baik dari email QRIS maupun input manual), kini bisa dipecah menjadi beberapa komponen item (mis. Rp 20.000 → Es Teh Rp 5.000 + Nasi Ayam Geprek Rp 15.000) dengan tombol cepat **Isi Sisa**, **Bagi Rata**, kategori & pos budget masing-masing komponen, tanpa dobel hitung di saldo maupun laporan.

### Peningkatan & Migrasi
- Migrasi database non-destruktif (`v2 → v3`) agar seluruh data lama tetap aman saat update tanpa uninstall.
- Backup & Restore `.json` diperbarui ke format v3 untuk menyertakan info pecahan transaksi (tetap kompatibel dengan cadangan v1 & v2).

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
