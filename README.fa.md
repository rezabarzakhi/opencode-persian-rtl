<p align="center">
  <img src="assets/banner.svg" alt="راست‌چین فارسی برای اوپن‌کد" width="900">
</p>

# راست‌چین فارسی برای اوپن‌کد

[![ویندوز](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows)](https://www.microsoft.com/windows)
[![پاورشل](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell)](https://learn.microsoft.com/powershell/)
[![مجوز](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![آزمون](https://github.com/rezabarzakhi/opencode-persian-rtl/actions/workflows/check.yml/badge.svg)](https://github.com/rezabarzakhi/opencode-persian-rtl/actions/workflows/check.yml)
[![انتشار](https://img.shields.io/github/v/release/rezabarzakhi/opencode-persian-rtl?color=7C3AED)](https://github.com/rezabarzakhi/opencode-persian-rtl/releases/latest)

تشخیص خودکار جهت متن‌های فارسی و عربی به همراه فونت وزیرمتن برای نسخهٔ رومیزی اوپن‌کد در ویندوز.

> [!IMPORTANT]
> این پروژه یک اصلاح غیررسمی برای رابط برنامه است و وابستگی رسمی به سازندگان اوپن‌کد ندارد. پس از به‌روزرسانی برنامه ممکن است نیاز باشد نصب‌کننده را دوباره اجرا کنید.

**[English documentation](README.md)**

## عملکرد

هر بخش متنی به‌صورت مستقل بررسی می‌شود:

| محتوا | نتیجه |
| --- | --- |
| دارای نویسهٔ فارسی یا عربی | راست‌به‌چپ و راست‌چین |
| کاملاً لاتین | چپ‌به‌راست و چپ‌چین |
| کد | همیشه چپ‌به‌راست |

فونت وزیرمتن نیز برای حساب کاربری فعلی ویندوز نصب و در رابط برنامه استفاده می‌شود.

## ویژگی‌های ایمنی

- ساختار و محتوای فایل‌های بومی بستهٔ برنامه حفظ و اعتبارسنجی می‌شود.
- نتیجه پیش از تغییر برنامه آزمایش می‌شود.
- جایگزینی بسته به‌صورت اتمی انجام می‌شود.
- هش نسخهٔ اصلی و اصلاح‌شده ثبت می‌شود.
- بازیابی ناسازگار پس از به‌روزرسانی برنامه متوقف می‌شود.
- فونت از نشانی ثابت دریافت و با هش معتبر بررسی می‌شود.
- وابستگی بسته‌بندی از قفل دقیق و بدون اجرای اسکریپت جانبی نصب می‌شود.
- تغییر هم‌زمان برنامه پیش از جایگزینی نهایی شناسایی می‌شود.
- اجرای دوباره باعث تزریق چندبارهٔ تغییرات نمی‌شود.

## پیش‌نیازها

- ویندوز ده یا یازده
- نسخهٔ رومیزی اوپن‌کد
- پاورشل نسخهٔ پنج و یک یا جدیدتر
- نود نسخهٔ بیست‌ودو و دوازده یا جدیدتر به همراه مدیر بسته
- دسترسی اینترنت هنگام نصب

## نصب

ابتدا همهٔ پنجره‌های اوپن‌کد را ببندید. سپس پاورشل را در پوشهٔ پروژه باز کنید و فرمان زیر را اجرا کنید:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-OpenCodePersianRTL.ps1
```

پس از پایان نصب، برنامه را دوباره اجرا کنید.

اگر برنامه در مسیر دیگری نصب شده است:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-OpenCodePersianRTL.ps1 -AppAsar "C:\path\to\resources\app.asar"
```

برای نصب‌نکردن فونت:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-OpenCodePersianRTL.ps1 -SkipFontInstall
```

## بازیابی

برنامه را ببندید و فرمان زیر را اجرا کنید:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-OpenCodePersianRTL.ps1 -Action Restore
```

بازیابی تنها زمانی انجام می‌شود که هش بستهٔ فعلی و نسخهٔ پشتیبان معتبر باشد. فونت وزیرمتن حذف نمی‌شود، چون ممکن است برنامه‌های دیگر نیز از آن استفاده کنند.

## به‌روزرسانی برنامه

به‌روزرسانی اوپن‌کد معمولاً تغییرات رابط را حذف می‌کند. اگر راست‌چین از بین رفت، برنامه را ببندید و نصب‌کننده را دوباره اجرا کنید.

## سازگاری

این نسخه با نسخهٔ زیر آزمایش شده است:

```text
OpenCode Desktop 1.18.5
```

نصب‌کننده در صورت تغییر ناسازگار ساختار رابط، پیش از دست‌کاری برنامه متوقف می‌شود.

## مجوز

کد پروژه با مجوز آزاد ام‌آی‌تی منتشر شده است. اجزای جانبی مجوزهای خود را حفظ می‌کنند.
