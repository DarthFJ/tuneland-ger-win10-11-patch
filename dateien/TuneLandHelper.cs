// Hilfsfunktionen für den TuneLand-Patch: CUE/BIN und echte CDs lesen, Musik nach OGG umwandeln,
// Spielfenster finden und den Bildausschnitt für Magpie bestimmen.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace TuneLand
{
    public class AudioTrack
    {
        public int Number;
        public long StartSector;   // in der Quelle (Datei bzw. CD-LBA)
        public long Sectors;
        public string File;        // null bei echter CD
    }

    public interface IPcmSource
    {
        void CopyTrack(AudioTrack t, Stream dst);
        bool Parallel { get; }
    }

    // ---------- CUE/BIN ----------
    public static class Cue
    {
        const int RawSector = 2352;

        static long Msf(string m)
        {
            var p = m.Split(':');
            return (long.Parse(p[0]) * 60 + long.Parse(p[1])) * 75 + long.Parse(p[2]);
        }

        class Entry { public int No; public string Type; public string File; public long Idx0 = -1; public long Idx1 = -1; }

        // Liefert alle Tracks; Daten-Tracks haben File gesetzt, aber werden vom Aufrufer gefiltert
        public static List<AudioTrack> ParseAudio(string cuePath, out string firstDataFile)
        {
            string dir = Path.GetDirectoryName(cuePath);
            var entries = new List<Entry>();
            string curFile = null;
            Entry cur = null;
            foreach (var raw in System.IO.File.ReadAllLines(cuePath, Encoding.Default))
            {
                var line = raw.Trim();
                Match m;
                if ((m = Regex.Match(line, "^FILE\\s+\"?(.+?)\"?\\s+(\\S+)$", RegexOptions.IgnoreCase)).Success)
                {
                    if (!m.Groups[2].Value.Equals("BINARY", StringComparison.OrdinalIgnoreCase))
                        throw new Exception("Diese CUE nutzt Dateien vom Typ " + m.Groups[2].Value + " – unterstützt wird nur BINARY (BIN).");
                    curFile = Path.Combine(dir, m.Groups[1].Value);
                }
                else if ((m = Regex.Match(line, "^TRACK\\s+(\\d+)\\s+(\\S+)", RegexOptions.IgnoreCase)).Success)
                {
                    cur = new Entry { No = int.Parse(m.Groups[1].Value), Type = m.Groups[2].Value.ToUpperInvariant(), File = curFile };
                    entries.Add(cur);
                }
                else if (cur != null && (m = Regex.Match(line, "^INDEX\\s+(\\d+)\\s+(\\d+:\\d+:\\d+)", RegexOptions.IgnoreCase)).Success)
                {
                    int idx = int.Parse(m.Groups[1].Value);
                    if (idx == 0) cur.Idx0 = Msf(m.Groups[2].Value);
                    if (idx == 1) cur.Idx1 = Msf(m.Groups[2].Value);
                }
            }

            firstDataFile = null;
            var result = new List<AudioTrack>();
            for (int i = 0; i < entries.Count; i++)
            {
                var e = entries[i];
                if (e.Type != "AUDIO")
                {
                    if (firstDataFile == null) firstDataFile = e.File;
                    continue;
                }
                long end;
                if (i + 1 < entries.Count && entries[i + 1].File == e.File)
                    end = entries[i + 1].Idx0 >= 0 ? entries[i + 1].Idx0 : entries[i + 1].Idx1;
                else
                    end = new FileInfo(e.File).Length / RawSector;
                result.Add(new AudioTrack { Number = e.No, File = e.File, StartSector = e.Idx1, Sectors = end - e.Idx1 });
            }
            return result;
        }

        // Volume-Label aus dem ISO-9660-Header einer BIN (MODE1/2352 oder 2048)
        public static string ReadVolumeLabel(string binPath)
        {
            try
            {
                using (var fs = System.IO.File.OpenRead(binPath))
                {
                    foreach (var layout in new[] { new[] { 2352, 16 }, new[] { 2048, 0 } })
                    {
                        var buf = new byte[2048];
                        fs.Seek(16L * layout[0] + layout[1], SeekOrigin.Begin);
                        if (fs.Read(buf, 0, 2048) < 2048) continue;
                        if (buf[0] == 1 && Encoding.ASCII.GetString(buf, 1, 5) == "CD001")
                            return Encoding.ASCII.GetString(buf, 40, 32).Trim();
                    }
                }
            }
            catch { }
            return null;
        }
    }

    public class BinSource : IPcmSource
    {
        public bool Parallel { get { return true; } }

        public void CopyTrack(AudioTrack t, Stream dst)
        {
            using (var fs = new FileStream(t.File, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16))
            {
                fs.Seek(t.StartSector * 2352, SeekOrigin.Begin);
                var buf = new byte[2352 * 64];
                long left = t.Sectors * 2352;
                while (left > 0)
                {
                    int n = fs.Read(buf, 0, (int)Math.Min(buf.Length, left));
                    if (n <= 0) break;
                    dst.Write(buf, 0, n);
                    left -= n;
                }
            }
        }
    }

    // ---------- echte CD (Audiotracks per Raw-Read) ----------
    public class CdSource : IPcmSource, IDisposable
    {
        const uint IOCTL_CDROM_READ_TOC = 0x00024000;
        const uint IOCTL_CDROM_RAW_READ = 0x0002403E;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inBuf, int inSize, byte[] outBuf, int outSize, out int returned, IntPtr ov);

        readonly SafeFileHandle handle;
        public bool Parallel { get { return false; } }

        public CdSource(char drive)
        {
            handle = CreateFile("\\\\.\\" + drive + ":", 0x80000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
            if (handle.IsInvalid) throw new IOException("Laufwerk " + drive + ": lässt sich nicht öffnen.");
        }

        public void Dispose() { handle.Dispose(); }

        // Audiotracks laut Inhaltsverzeichnis; leer, wenn das Laufwerk keine anbietet (z. B. WinCDEmu)
        public List<AudioTrack> ReadAudioTracks()
        {
            var toc = new byte[804];
            int ret;
            var list = new List<AudioTrack>();
            if (!DeviceIoControl(handle, IOCTL_CDROM_READ_TOC, null, 0, toc, toc.Length, out ret, IntPtr.Zero)) return list;
            int first = toc[2], last = toc[3];
            var starts = new List<long>();
            var audio = new List<bool>();
            var numbers = new List<int>();
            for (int i = 0; i <= last - first + 1; i++)
            {
                int o = 4 + i * 8;
                starts.Add((toc[o + 5] * 60L + toc[o + 6]) * 75 + toc[o + 7] - 150);
                audio.Add((toc[o + 1] & 0x04) == 0);   // Control (untere 4 Bit): 0x4 = Datentrack
                numbers.Add(toc[o + 2]);
            }
            for (int i = 0; i < last - first + 1; i++)
            {
                if (!audio[i]) continue;
                list.Add(new AudioTrack { Number = numbers[i], StartSector = starts[i], Sectors = starts[i + 1] - starts[i] });
            }
            return list;
        }

        public void CopyTrack(AudioTrack t, Stream dst)
        {
            const int chunk = 20;
            var outBuf = new byte[chunk * 2352];
            var inBuf = new byte[16];
            long pos = t.StartSector, end = t.StartSector + t.Sectors;
            while (pos < end)
            {
                int count = (int)Math.Min(chunk, end - pos);
                BitConverter.GetBytes(pos * 2048).CopyTo(inBuf, 0);
                BitConverter.GetBytes(count).CopyTo(inBuf, 8);
                BitConverter.GetBytes(2).CopyTo(inBuf, 12);   // CDDA
                int ret = 0;
                bool ok = false;
                for (int attempt = 0; attempt < 5 && !ok; attempt++)
                    ok = DeviceIoControl(handle, IOCTL_CDROM_RAW_READ, inBuf, 16, outBuf, count * 2352, out ret, IntPtr.Zero);
                if (!ok)
                {
                    // Unlesbare Stelle mit Stille überbrücken statt abzubrechen
                    Array.Clear(outBuf, 0, count * 2352);
                    ret = count * 2352;
                }
                dst.Write(outBuf, 0, ret);
                pos += count;
            }
        }
    }

    // ---------- Umwandlung nach OGG ----------
    public static class Encoder
    {
        public static int Done;
        public static int Total;
        public static string Error;
        public static bool Finished;

        public static void Start(string oggenc, IPcmSource source, List<AudioTrack> tracks, string outDir)
        {
            Done = 0; Total = tracks.Count; Error = null; Finished = false;
            Directory.CreateDirectory(outDir);
            var queue = new Queue<AudioTrack>(tracks);
            int workers = source.Parallel ? Math.Max(1, Math.Min(Environment.ProcessorCount, 6)) : 1;
            int running = workers;
            for (int w = 0; w < workers; w++)
            {
                var th = new Thread(() =>
                {
                    try
                    {
                        while (true)
                        {
                            AudioTrack t;
                            lock (queue) { if (queue.Count == 0 || Error != null) break; t = queue.Dequeue(); }
                            EncodeOne(oggenc, source, t, Path.Combine(outDir, string.Format("Track{0:D2}.ogg", t.Number)));
                            Interlocked.Increment(ref Done);
                        }
                    }
                    catch (Exception ex) { Error = ex.Message; }
                    finally { if (Interlocked.Decrement(ref running) == 0) Finished = true; }
                });
                th.IsBackground = true;
                th.Start();
            }
        }

        static void EncodeOne(string oggenc, IPcmSource source, AudioTrack t, string outFile)
        {
            var psi = new ProcessStartInfo(oggenc,
                "--raw --raw-bits=16 --raw-chan=2 --raw-rate=44100 --raw-endianness 0 -q 5 --quiet -o \"" + outFile + "\" -")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardError = true
            };
            using (var p = Process.Start(psi))
            {
                p.ErrorDataReceived += (s, e) => { };
                p.BeginErrorReadLine();
                source.CopyTrack(t, p.StandardInput.BaseStream);
                p.StandardInput.Close();
                p.WaitForExit();
                if (p.ExitCode != 0 || !File.Exists(outFile))
                    throw new Exception("Track " + t.Number + " konnte nicht umgewandelt werden.");
            }
        }
    }

    public static class Shell
    {
        [DllImport("shell32.dll")] static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);

        // SHCNE_ASSOCCHANGED: Explorer lädt Symbole neu
        public static void Refresh() { SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero); }
    }

    // ---------- Symbole aus 16-Bit-Programmen (NE-Format) ----------
    // Windows liest Symbole aus Windows-3.x-Programmen nicht mehr aus, deshalb hier von Hand aus der Ressourcentabelle
    public static class NeIcon
    {
        const int RT_ICON = 0x8003, RT_GROUP_ICON = 0x800E;

        class Res { public int Type; public int Id; public long Offset; public int Length; }

        public static bool Save(string exePath, string icoPath)
        {
            byte[] f = File.ReadAllBytes(exePath);
            if (f.Length < 0x40 || f[0] != 'M' || f[1] != 'Z') return false;
            int ne = BitConverter.ToInt32(f, 0x3C);
            if (ne + 0x40 > f.Length || f[ne] != 'N' || f[ne + 1] != 'E') return false;

            int p = ne + BitConverter.ToUInt16(f, ne + 0x24);
            int shift = BitConverter.ToUInt16(f, p);
            p += 2;
            var list = new List<Res>();
            while (true)
            {
                int type = BitConverter.ToUInt16(f, p);
                if (type == 0) break;
                int count = BitConverter.ToUInt16(f, p + 2);
                p += 8;
                for (int i = 0; i < count; i++, p += 12)
                {
                    list.Add(new Res
                    {
                        Type = type,
                        Id = BitConverter.ToUInt16(f, p + 6),
                        Offset = (long)BitConverter.ToUInt16(f, p) << shift,
                        Length = BitConverter.ToUInt16(f, p + 2) << shift
                    });
                }
            }

            var group = list.Find(r => r.Type == RT_GROUP_ICON);
            if (group == null) return false;
            int g = (int)group.Offset;
            int n = BitConverter.ToUInt16(f, g + 4);

            // ICO: Kopf (6) + Einträge (16) + Bilddaten
            var images = new List<byte[]>();
            var entries = new List<byte[]>();
            for (int i = 0; i < n; i++)
            {
                int e = g + 6 + i * 14;
                int id = BitConverter.ToUInt16(f, e + 12) | 0x8000;
                var icon = list.Find(r => r.Type == RT_ICON && r.Id == id);
                if (icon == null) continue;
                int size = BitConverter.ToInt32(f, e + 8);
                var data = new byte[Math.Min(size, icon.Length)];
                Array.Copy(f, icon.Offset, data, 0, data.Length);
                images.Add(data);
                var entry = new byte[16];
                Array.Copy(f, e, entry, 0, 8);
                BitConverter.GetBytes(data.Length).CopyTo(entry, 8);
                entries.Add(entry);
            }
            if (images.Count == 0) return false;

            using (var o = new FileStream(icoPath, FileMode.Create))
            using (var w = new BinaryWriter(o))
            {
                w.Write((ushort)0); w.Write((ushort)1); w.Write((ushort)images.Count);
                int offset = 6 + 16 * images.Count;
                for (int i = 0; i < images.Count; i++)
                {
                    BitConverter.GetBytes(offset).CopyTo(entries[i], 12);
                    w.Write(entries[i]);
                    offset += images[i].Length;
                }
                foreach (var img in images) w.Write(img);
            }
            return true;
        }
    }

    // ---------- Spielfenster und Bildausschnitt ----------
    public static class GameWindow
    {
        delegate bool EnumProc(IntPtr h, IntPtr l);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
        [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);

        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DEVMODE
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
            public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
            public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
            public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
        }

        public static string ClassName(IntPtr h)
        {
            var sb = new StringBuilder(256);
            GetClassName(h, sb, 256);
            return sb.ToString();
        }

        // Sichtbares Hauptfenster von TuneLand (Klasse WIN16…VIEW_CLASS) im angegebenen Prozess
        public static IntPtr Find(int pid)
        {
            IntPtr found = IntPtr.Zero;
            EnumWindows((h, l) =>
            {
                uint p;
                GetWindowThreadProcessId(h, out p);
                if (p == pid && IsWindowVisible(h) && ClassName(h).EndsWith("VIEW_CLASS")) { found = h; return false; }
                return true;
            }, IntPtr.Zero);
            return found;
        }

        // Faktor zwischen echten Bildschirmpixeln und den Koordinaten, die dieser (DPI-unaware) Prozess sieht
        public static double PhysicalScale()
        {
            var dm = new DEVMODE();
            dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            if (!EnumDisplaySettings(null, -1, ref dm) || dm.dmPelsWidth == 0) return 1.0;
            return (double)dm.dmPelsWidth / GetSystemMetrics(0);
        }

        // Sucht die zentrierte 4:3-Bildfläche; Rückgabe {links, oben, rechts, unten} in logischen Pixeln oder null
        public static int[] DetectPicture(IntPtr h)
        {
            RECT r;
            if (!GetClientRect(h, out r) || r.Right < 100 || r.Bottom < 100) return null;
            int w = r.Right, ht = r.Bottom;
            using (var bmp = new Bitmap(w, ht))
            {
                using (var g = Graphics.FromImage(bmp))
                {
                    IntPtr dc = g.GetHdc();
                    PrintWindow(h, dc, 3);   // PW_CLIENTONLY | PW_RENDERFULLCONTENT
                    g.ReleaseHdc(dc);
                }
                int y = ht / 2, x = w / 2;
                int left = -1, right = -1, top = -1, bottom = -1;
                for (int i = 0; i < w; i++) if (Bright(bmp.GetPixel(i, y))) { left = i; break; }
                for (int i = w - 1; i >= 0; i--) if (Bright(bmp.GetPixel(i, y))) { right = i; break; }
                for (int i = 0; i < ht; i++) if (Bright(bmp.GetPixel(x, i))) { top = i; break; }
                for (int i = ht - 1; i >= 0; i--) if (Bright(bmp.GetPixel(x, i))) { bottom = i; break; }
                if (left < 0 || top < 0) return null;
                int cw = right - left + 1, ch = bottom - top + 1;
                // Plausibel nur, wenn zentriert und im Seitenverhältnis 4:3
                if (Math.Abs(left - (w - 1 - right)) > 3 || Math.Abs(top - (ht - 1 - bottom)) > 3) return null;
                if (Math.Abs(cw * 3.0 / (ch * 4.0) - 1.0) > 0.02) return null;
                return new[] { left, top, w - 1 - right, ht - 1 - bottom, w, ht };
            }
        }

        static bool Bright(Color c) { return c.R + c.G + c.B > 30; }
    }
}
