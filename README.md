# Sakuin

Aplikasi pencatat keuangan Android **offline-first**, privat (tanpa server, tanpa iklan, tanpa akun), super cepat, dan ringan. Seluruh data keuangan tersimpan 100% lokal di perangkat; koneksi internet hanya dipakai secara opsional untuk cek & unduh pembaruan resmi dari GitHub Releases.

- **Application ID:** `id.rakavalrizqy.sakuin`
- **Minimum Android:** Android 7.0 (API 24)
- **Bahasa & Mata Uang:** Bahasa Indonesia, Rupiah (IDR)
- **Build & Release:** 100% melalui GitHub Actions (tidak ada build/release lokal)

## Fitur Utama

- **Input Super Cepat (1–2 ketukan):** Item Memory otomatis + autocomplete, Item Cepat di Beranda (dengan mode *Simpan Langsung* opsional), Duplikat transaksi, Smart Defaults, Keypad nominal kustom (`000`, `15k`, `1,5jt`, kalkulator `+ − × ÷`), dan Transaksi Berulang.
- **Saku / Dompet + Pos Budget:** Buat dompet sendiri (Tunai, Rekening Bank, E-Wallet, Lainnya), bagi saldo dalam satu saku menjadi beberapa **Pos Budget** (mis. Uang Harian & Tabungan + Saldo Bebas), alokasi manual, pindah antar pos di saku yang sama, transfer lintas saku langsung ke pos tertentu (+ biaya admin opsional), koreksi saldo, dan detail dompet.
- **Auto QRIS (Gmail) & Pecah Transaksi:** Hubungkan Gmail via IMAP + App Password (*read-only*, tanpa setup Google Cloud) untuk menarik email pengeluaran QRIS ke antrean review, serta pecah satu transaksi menjadi beberapa komponen item (mis. Rp 20.000 → Es Teh Rp 5.000 + Nasi Ayam Geprek Rp 15.000) dengan kategori & pos budget masing-masing.
- **Pembaruan Otomatis dari Aplikasi:** Cek rilis terbaru GitHub secara otomatis saat dibuka (bisa dimatikan di Pengaturan), tampilkan rangkuman perubahan dari `CHANGELOG.md`, unduh APK yang sesuai ABI perangkat langsung di aplikasi, lalu buka pemasang Android tanpa perlu uninstall.
- **Pengeluaran & Pemasukan:** Pengelompokan per hari dengan subtotal, pencarian & filter lengkap, hapus dengan **Urungkan (Undo)**, warna semantik konsisten (**merah = pengeluaran, hijau = pemasukan**).
- **Hutang-Piutang:** Kontak teman, dua arah (*Saya berutang* & *Mereka berutang*), cicilan parsial + progress bar, efek ke dompet opsional (tanpa merusak laporan arus kas), ringkasan per orang, pengingat jatuh tempo, dan bagikan pengingat penagihan via share sheet.
- **Laporan & Anggaran:** Tanggal mulai periode kustom (1–28, mis. tanggal gajian), grafik `CustomPainter` ringan (Donut interaktif & Tren), perbandingan periode sebelumnya, anggaran bulanan total & per kategori dengan peringatan 80%/100% serta batas harian aman, ekspor **CSV** dan **PDF**.
- **Keamanan & Privasi:** Kunci aplikasi PIN 4–6 digit (hash + salt di `flutter_secure_storage`) + Biometrik, kunci otomatis, sembunyikan saldo, blokir screenshot (`FLAG_SECURE`), dan Backup/Restore file JSON lewat Storage Access Framework (bisa simpan langsung ke Google Drive tanpa izin internet).

---

## Update Tanpa Uninstall

Sakuin dikonfigurasi agar setiap rilis baru **selalu bisa dipasang langsung menimpa versi lama tanpa uninstall** (data SQLite dan pengaturan tetap aman):

1. **Application ID permanen:** `id.rakavalrizqy.sakuin` (jangan pernah diubah).
2. **Release keystore konsisten:** Workflow `release.yml` wajib memakai keystore tetap dari GitHub Secrets dan akan gagal jika secrets belum diisi (tidak pernah fallback ke debug key).
3. **Version code selalu naik otomatis:** `release.yml` memakai `max(pubspec build number, github.run_number)` sehingga setiap build rilis selalu punya `versionCode` lebih tinggi.
4. **Migrasi database aman:** Skema Drift memakai `MigrationStrategy` non-destruktif (`onCreate` + `onUpgrade`) agar data lama selalu dipertahankan.

> **Penting:** Simpan cadangan file keystore (`.jks`) dan kata sandinya di tempat aman. Jika keystore hilang dan diganti keystore baru, Android akan menolak update tanpa uninstall.

---

## Setup Keystore & GitHub Secrets (Sekali Saja)

### 1. Buat Keystore Release (sekali saja)

Jalankan perintah berikut di terminal lokal (membutuhkan JDK / `keytool`):

```bash
keytool -genkey -v \
  -keystore sakuin-release.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias sakuin
```

> **Jangan pernah commit** file `.jks` ke Git (sudah diblokir di `.gitignore`).

### 2. Ubah Keystore ke Base64

- **Windows (PowerShell):**
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("sakuin-release.jks")) | Set-Clipboard
  ```
- **Linux / macOS:**
  ```bash
  base64 -w 0 sakuin-release.jks
  ```

### 3. Masukkan Secrets ke GitHub Repository

Buka repo GitHub → **Settings → Secrets and variables → Actions → New repository secret**, lalu tambahkan 4 secret berikut:

| Secret | Isi |
|---|---|
| `KEYSTORE_BASE64` | String Base64 dari `sakuin-release.jks` |
| `KEYSTORE_PASSWORD` | Password keystore yang dibuat di langkah 1 |
| `KEY_ALIAS` | Alias key (contoh: `sakuin`) |
| `KEY_PASSWORD` | Password key |

---

## Cara Memicu Release & Mengunduh APK

### Opsi A: Lewat Git Tag (Disarankan)

```bash
git tag v1.0.0
git push origin v1.0.0
```

Untuk update berikutnya (tanpa perlu uninstall di HP):

```bash
git tag v1.0.1
git push origin v1.0.1
```

### Opsi B: Manual (`workflow_dispatch`)

Buka tab **Actions → Release Android APK → Run workflow**, isi `version_name` jika ingin mengganti nomor versi, lalu klik **Run workflow**.

### Cara Mengunduh & Memasang APK

1. Buka halaman **Releases** di repo GitHub.
2. Untuk Redmi Note 11 Pro 5G dan sebagian besar HP Android modern (64-bit ARM), unduh **`app-arm64-v8a-release.apk`**.
3. Ketuk file APK untuk install atau update langsung di atas versi sebelumnya.

---

## Mengukur Ukuran APK & Profil Performa

- **Ukuran APK:** Setiap run workflow `Release Android APK` otomatis menampilkan tabel ukuran setiap APK pada **GitHub Actions Step Summary** (target `app-arm64-v8a-release.apk` < 20 MB). Anda juga bisa mengecek ukuran file di halaman **GitHub Releases**.
- **Profil Performa (opsional, untuk pemilik proyek):** Jika ingin mengukur frame timing (120 Hz) dan cold start di perangkat fisik lewat Flutter DevTools, jalankan profile mode di perangkat target dengan `adb logcat -s ActivityTaskManager` untuk melihat metrik `Displayed id.rakavalrizqy.sakuin/.MainActivity` (target ≤ 1000 ms).
