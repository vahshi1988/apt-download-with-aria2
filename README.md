# apt-download-with-aria2

<div dir="rtl">

دانلود سریع فایل‌ها و پکیج‌های `apt` با [aria2](https://aria2.github.io/) — چند اتصاله، هم‌زمان و قابل ادامه.

این ریپو شامل دو اسکریپت است:

| فایل | کاربرد |
|---|---|
| `aria2-dl.sh` | هر لینک دانلودی را می‌گیرد و با aria2 (تا ۱۶ اتصال) دانلود می‌کند |
| `apt-a2.sh` | پکیج‌های `apt` را با `aria2-dl.sh` دانلود می‌کند و بعد `apt` نصبشان می‌کند |

## پیش‌نیازها

</div>

```bash
sudo apt install aria2 curl
```

<div dir="rtl">

## نصب

</div>

```bash
git clone https://github.com/vahshi1988/apt-download-with-aria2.git
cd apt-download-with-aria2
chmod +x aria2-dl.sh apt-a2.sh
mkdir -p ~/.local/bin
ln -s "$PWD/aria2-dl.sh" ~/.local/bin/a2
ln -s "$PWD/apt-a2.sh"   ~/.local/bin/apt-a2
```

<div dir="rtl">

> دو فایل باید کنار هم باشند (یا مسیر `aria2-dl.sh` را با متغیر `A2DL` بدهید).

---

## aria2-dl.sh

</div>

```bash
a2 "https://example.com/file.zip"              # دانلود با 16 اتصال در ~/Downloads
a2                                              # لینک را می‌پرسد
a2 -d ~/Videos -o movie.mkv "URL"               # پوشه و نام دلخواه
a2 "URL1" "URL2" "URL3"                         # چند لینک (تا 5 تا هم‌زمان)
a2 -i links.txt                                 # لیست لینک‌ها از فایل
a2 -p "URL"                                     # فقط دستور aria2c را چاپ کن
ARIA2_SECRET=token a2 -r "URL"                  # ارسال به aria2 در حال اجرا (RPC)
```

<div dir="rtl">

| گزینه | توضیح |
|---|---|
| `-d DIR` | پوشه ذخیره (پیش‌فرض: `~/Downloads`) |
| `-o NAME` | نام فایل خروجی (فقط برای یک لینک) |
| `-x N` | تعداد اتصال (پیش‌فرض و حداکثر: 16) |
| `-i FILE` | فایل حاوی لینک‌ها (هر خط یک لینک) |
| `-R URL` | Referer |
| `-c FILE` | فایل کوکی (فرمت Netscape) |
| `-H HEADER` | هدر اضافه (قابل تکرار) |
| `-p` | فقط دستور را چاپ کن |
| `-r` | ارسال به aria2 RPC (`ARIA2_RPC`، `ARIA2_SECRET`) |

---

## apt-a2.sh

</div>

```bash
apt-a2 install htop vlc
apt-a2 upgrade
apt-a2 full-upgrade
apt-a2 --dry-run upgrade      # فقط نشان بده چه چیزی دانلود می‌شود
apt-a2 update                 # بقیه دستورها مستقیم به apt می‌روند
```

<div dir="rtl">

خودش در صورت نیاز `sudo` می‌گیرد.

### نحوه کار

1. لیست لینک پکیج‌ها با `apt-get --print-uris` گرفته می‌شود.
2. فایل‌هایی که در کش هستند رد می‌شوند و بقیه با `aria2-dl.sh` دانلود می‌شوند.
3. فایل‌های کامل‌شده به `/var/cache/apt/archives` منتقل می‌شوند.
4. `apt` اجرا می‌شود، هش فایل‌ها را خودش بررسی می‌کند و از کش نصب می‌کند.
   اگر دانلود پکیجی با aria2 شکست بخورد، `apt` خودش آن را دانلود می‌کند.

| متغیر | توضیح |
|---|---|
| `A2DL` | مسیر `aria2-dl.sh` (پیش‌فرض: کنار `apt-a2.sh`) |
| `A2_CONN` | تعداد اتصال برای هر فایل (پیش‌فرض: 16) |

## لایسنس

[MIT](LICENSE)

</div>
