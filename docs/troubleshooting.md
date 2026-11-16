# Troubleshooting

## fastboot devices kosong saat ponsel sudah di mode Fastboot

Gejala: layar ponsel menunjukkan **FASTBOOT mode**, tapi `fastboot devices` tidak menampilkan apa-anya.

Di Windows, ini biasanya berarti **driver antarmuka bootloader belum terpasang** (Device Manager menunjukkan perangkat "Android" dengan tanda seru kuning, **Error Code 28**).

### Cara pemasangan (tanpa installer)

1. Unduh [Google USB Driver untuk Windows](https://dl.google.com/android/repository/usb_driver_r13-windows.zip).
2. Ekstrak ke folder, misalnya `C:\usb_driver`.
3. Buka **Device Manager** (`devmgmt.msc`).
4. Klik kanan perangkat **"Android"** bertanda seru kuning → **Update driver**.
5. Pilih **Browse my computer for drivers**, masukkan `C:\usb_driver`.
6. Centang **Include subfolders**, klik **Next**.
7. Pilih **Android Bootloader Interface** → **Next** → **Yes** jika ada peringatan kompatibilitas.

Setelah driver terpasang, `fastboot devices` akan menampilkan serial perangkat.

### Jika Windows menolak ("best driver is already installed")

Device Manager → klik kanan **Android** → **Update driver** → **Browse my computer** → **Let me pick from a list** → **Have Disk** → pilih `C:\usb_driver\android_winusb.inf` → pilih **Android Bootloader Interface**.

## Masuk ke mode Fastboot

1. Matikan ponsel.
2. Tekan dan tahan **Volume Down + Power** sampai layar fastboot muncul.
3. Sambungkan kabel USB data.
4. Jalankan `fastboot devices` (atau `fastboot.exe devices` di Windows).

## Masuk ke mode Recovery (TWRP)

1. Matikan ponsel.
2. Tekan dan tahan **Volume Up + Power** sampai TWRP muncul.
3. `adb devices` akan menampilkan perangkat.

## Uji boot RAM (non-destruktif)

```bash
fastboot boot build/boot-santoni.img
```

- Tidak menulis partisi; Android/TWRP tetap utuh.
- Jika gagal, reboot ponsel dan coba kembali.

## Platform-tools (adb + fastboot) otomatis

Repo ini tidak menyertakan binary adb/fastboot secara langsung. Skrip `scripts/lib/platform-tools.sh` akan mengunduh platform-tools resmi Google ke `.cache/platform-tools/<os>/` pada pertama kali dibutuhkan (Windows, Linux, dan macOS).

Jika host tidak punya koneksi internet, sediakan paket offline di `vendor/platform-tools/<os>/` (gitignored, dibagikan terpisah).

## Boot tidak berhasil setelah `fastboot boot`

- Pastikan boot image sesuai page size perangkat (santoni: 2048, mido: 2048, sagit: 4096).
- Pastikan DTB cocok dengan perangkat (`msm8940-xiaomi-santoni.dtb`, `msm8953-xiaomi-mido.dtb`, `msm8998-xiaomi-sagit.dtb`).
- Kernel mainline untuk perangkat ini belum punya initramfs/rootfs; boot akan berhenti setelah command line kernel. P3 akan menambahkan initramfs + rootfs Debian/Ubuntu.

## Kontak

Laporkan masalah baru di [GitHub Issues](https://github.com/helmiau/debiandroid/issues) dengan output `fastboot devices`, `fastboot getvar unlocked`, dan `dmesg` dari ponsel jika tersedia.
