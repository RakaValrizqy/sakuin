# Catatan Rilis Sakuin

## v1.7.2
### Perbaikan & Peningkatan
- **Perbaikan Pos Budget "Hantu" dari Dompet Arsip:** Memperbaiki query daftar pos aktif agar pos budget milik dompet yang sudah diarsipkan tidak lagi ikut terhitung di Ringkasan Pos Budget (tab Dompet) maupun di *Safe-to-Spend*.
- **Numpad Bawaan HP + Shortcut `rb` / `jt` di Catat Transaksi:** Menghapus keypad buatan aplikasi pada layar Catat Transaksi agar seluruh input nominal di Sakuin konsisten menggunakan **numpad bawaan HP** dengan pemisah titik otomatis, dilengkapi bar tombol cepat **`rb (×1.000)`**, **`jt (×1 jt)`**, **`+10 rb`**, **`+50 rb`**, **`+100 rb`**, dan **`Hapus`**.
- **Perbaikan Koneksi Gmail di Wi-Fi Kampus/Kantor:** Memprioritaskan koneksi **IPv4** untuk mencegah error `errno = 101 (Network is unreachable)` pada Wi-Fi yang rute IPv6-nya bermasalah, disertai pesan error yang jelas jika port IMAP 993 diblokir firewall Wi-Fi.

## v1.7.1
### Peningkatan & Perbaikan
- **Penggabungan Pos Budget Bernama Sama Lintas Saku:** Pos budget dengan nama yang sama di berbagai saku (mis. `Uang Harian` di Mandiri, BNI, & DANA, atau `Life Style` & `Lifestyle`) kini otomatis digabungkan menjadi **1 pilihan** di pengaturan *Safe-to-Spend* serta tampil dalam kartu **Ringkasan Pos Budget (Gabungan Semua Saku)** di tab **Dompet**.
- **Input Nama Item + Saran Otomatis saat Simpan QRIS:** Dialog *Simpan Pengeluaran QRIS* kini dilengkapi kolom **Nama item / transaksi** beserta chip saran dari riwayat item sebelumnya (ketuk saran langsung mengisi nama, kategori, & pos budget).
- **Pintasan Buka Setelan Terbatas (Android 13+/Xiaomi):** Menambahkan tombol pintasan langsung ke **Info Aplikasi Sakuin** di layar Auto Catat Notifikasi agar mudah membuka *Allow restricted settings* sebelum mengaktifkan Akses Notifikasi.

## v1.7.0
### Apa yang Baru
- **Batas Aman Belanja Harian (*Safe-to-Spend*) di Beranda:** Menampilkan jatah belanja aman per hari (plus progres pemakaian hari ini) yang dihitung dari sisa anggaran bulanan, pos budget pilihan, atau total saldo dibagi sisa hari periode berjalan. Ketuk kartunya untuk mengganti sumber dana kapan saja.
- **Auto-Catat dari Notifikasi HP (Opsional, 100% Lokal):** Menangkap notifikasi transaksi dari aplikasi bank & e-wallet Indonesia (Mandiri Livin', BCA, BRImo, BNI, BSI, GoPay, OVO, DANA, ShopeePay, SeaBank, Jago, Blu, dll.) langsung ke antrean Review — siap **Simpan**, **Pecah Item**, atau **Split Bill** tanpa perlu menunggu email.
- **Kalender Pengeluaran (*Spending Heatmap*) & Insight Periode di Laporan:** Kalender bulanan interaktif berwarna (*No-Spend Day* hingga hari boros — ketuk tanggal untuk melihat transaksi hari itu) plus kartu **Insight Periode** (jumlah *No-Spend Day*, proyeksi akhir periode, hari paling boros, item tersering, dan kategori paling naik/turun dibanding periode lalu).
- **Bagi Saldo Bebas (%) di Detail Saku & Edit Pemasukan:** Fitur pembagian persentase (%) kini juga bisa dipakai kapan saja dari Detail Saku (untuk membagi Saldo Bebas yang sudah ada) maupun dari layar Edit Transaksi Pemasukan.

## v1.6.0
### Apa yang Baru
- **Bagi Pemasukan Otomatis ke Pos Budget berdasarkan Persentase (%):** Setiap kali kamu mencatat **Pemasukan** pada saku yang memiliki pos budget, langsung tersedia opsi **Bagi per Persentase (%)** untuk membagikan dana masuk ke setiap pos budget dengan slider, input angka %, tombol cepat (`10%`, `20%`, `30%`, `50%`, `Isi sisa`, `Bagi rata`), serta kategori otomatis **Belum Dialokasikan (Saldo Bebas)** untuk menampung sisa persentase yang belum ditentukan. Template persentase juga otomatis diingat untuk pemasukan berikutnya di saku tersebut!

## v1.5.4
### Apa yang Baru
- **Split Bill Langsung dari Antrean QRIS (Gmail):** Setiap transaksi di antrean review Auto QRIS kini memiliki tombol **Split Bill** — bisa langsung dibagi ke beberapa orang (sama rata atau dipecah per item dengan saran nama otomatis & tombol *Isi sisa* yang mencocokkan total QRIS), lalu disimpan ke **Transaksi + Piutang/Hutang**, **Transaksi Biasa**, atau **Tidak Disimpan (Hanya Cek)**.

## v1.5.3
### Peningkatan & Perbaikan
- **Deteksi Email QRIS (Gmail) Lebih Akurat & Luas:** Memperbesar batas baca isi email HTML bank dari 32 KB ke 128 KB (agar struk email panjang tidak terpotong), menaikkan batas scan dari 80 ke 200 email terbaru, memperluas dukungan bank & subjek resi, serta mencegah disclaimer footer bank (seperti kata *"gagal"* atau *"promo"*) menolak struk QRIS yang sebenarnya berhasil.
- **Pecah Transaksi Pakai Istilah "Item" + Saran Nama Otomatis:** Seluruh label *"Komponen"* di layar Pecah Transaksi diganti menjadi **"Item"**, dan kolom nama item kini menampilkan saran (*suggestion chips*) otomatis berdasarkan riwayat item yang pernah kamu input (lengkap dengan pengisian otomatis harga terakhir & kategori saat diketuk).

## v1.5.2
### Perbaikan
- **Perbaikan Filter Batas Tanggal Auto QRIS (Gmail):** Antrean lama yang dibersihkan saat mengatur batas tanggal kini dihapus bersih (tidak ditandai *dismissed* permanen), sehingga ketika batas tanggal dimundurkan (mis. dari 26 Nov ke 25 Nov) atau dihapus, transaksi setelah batas baru otomatis muncul kembali & langsung disinkron ulang. Ditambahkan juga tombol **Pulihkan** (`↺`) di pojok atas layar Auto QRIS untuk mengembalikan transaksi yang sempat tersembunyi sebelumnya.

## v1.5.1
### Perbaikan Kritis
- **Perbaikan Force Close Saat Membuka Aplikasi (`v1.5.0`):** Menambahkan aturan ProGuard/R8 Full Mode lengkap untuk `WorkManager`, `AndroidX Startup`, `RoomDatabase`, `Google ML Kit`, dan `Firebase ComponentRegistrar` yang sebelumnya terpotong oleh R8 saat build release, serta menambahkan pelindung `Throwable` pada handler native Android.

## v1.5.0
### Apa yang Baru
- **Scan Struk Hybrid (Kamera, Galeri, & Share Gambar ke Sakuin):** Foto struk langsung dengan kamera, pilih dari galeri, atau langsung klik **Bagikan (Share)** dari Galeri/WhatsApp ke Sakuin! Default berjalan **100% offline dengan Google ML Kit** (dengan rekonstruksi baris otomatis), plus dukungan opsional **Gemini AI Vision** di Pengaturan dengan *fallback* otomatis ke offline jika sedang tidak ada sinyal.
- **Fitur Split Bill Lengkap:** Bagi hasil scan struk ke banyak orang, pilih siapa beli item apa (termasuk item patungan beberapa orang), pembagian pajak/service/diskon secara proporsional atau rata tanpa selisih 1 rupiah, tombol **Salin / Bagikan Rincian**, serta 3 opsi penyimpanan: **Transaksi + Piutang/Hutang**, **Transaksi Biasa saja**, atau **Tidak Disimpan (Hanya Cek)**.
- **Notifikasi Rilis Baru GitHub (Super Hemat Baterai):** Menggunakan Android `WorkManager` (1x/24 jam, hanya jalan saat ada internet & baterai tidak rendah, memakai header `If-None-Match` ETag 304) untuk memberi notifikasi otomatis saat versi Sakuin baru rilis di GitHub.

## v1.4.0
### Apa yang Baru
- **Batas Tanggal Sinkron Email QRIS:** Kini bisa mengatur tanggal batas di menu **Auto QRIS (Gmail)** (mis. pilih 25 November → transaksi pada tanggal 25 November dan sebelumnya tidak akan diperiksa maupun dimasukkan ke antrean review, lengkap dengan opsi membersihkan antrean lama yang sudah terlanjur masuk).
- **Navigasi Menu Utama Lebih Ringkas:** Bilah navigasi bawah kini berisi **Beranda • Dompet • Laporan • Lainnya**. Menu **Transaksi** dan **Hutang-Piutang** tersedia sebagai sub-menu cepat di **Beranda** (di samping kartu Total Saldo, Item Cepat, dan Transaksi Terbaru) serta di urutan atas tab **Lainnya**.

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
