param(
    [Parameter(Mandatory=$true)][string]$Cmd,
    [string]$Name = '',
    [int]$Ax = 0, [int]$Ay = 0, [int]$Aw = 0, [int]$Ah = 0,
    [int]$Scroll = 0,
    [string]$OutDir = 'promo_screens'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class PWin32 {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT pt);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int X, int Y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

  // 客户区在屏幕上的位置与尺寸，一次性返回，避免 PowerShell 端多次 P/Invoke
  public static int[] ClientBox(IntPtr h) {
    RECT cr; GetClientRect(h, out cr);
    POINT pt = new POINT { X = 0, Y = 0 };
    ClientToScreen(h, ref pt);
    return new int[] { pt.X, pt.Y, cr.Right, cr.Bottom };
  }
}
'@

[PWin32]::SetProcessDPIAware() | Out-Null  # 系统缩放非 100% 时坐标保持物理像素

function Get-App {
    $p = Get-Process -Name todo_app -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $p) { throw 'todo_app window not found' }
    return $p
}

switch ($Cmd) {
    'launch' {
        $exe = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\todo_app.exe'
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
        Start-Sleep -Seconds 8
        $p = Get-App
        [PWin32]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
        $cb = [PWin32]::ClientBox($p.MainWindowHandle)
        Write-Output ("client: {0},{1} {2}x{3}" -f $cb[0], $cb[1], $cb[2], $cb[3])
    }
    'rect' {
        $p = Get-App
        [PWin32]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
        $cb = [PWin32]::ClientBox($p.MainWindowHandle)
        Write-Output ("client: {0},{1} {2}x{3}" -f $cb[0], $cb[1], $cb[2], $cb[3])
    }
    'move' {
        # 目标：客户区 = Ax,Ay AwxAh。先放外框，再按外框/客户区偏差校正一轮
        $p = Get-App
        $h = $p.MainWindowHandle
        [PWin32]::ShowWindow($h, 9) | Out-Null  # SW_RESTORE（若最大化）
        Start-Sleep -Milliseconds 500
        [PWin32]::SetWindowPos($h, [IntPtr]::Zero, $Ax, $Ay, $Aw, $Ah, 0x0004) | Out-Null
        Start-Sleep -Milliseconds 800
        $ob = New-Object PWin32+RECT
        [PWin32]::GetWindowRect($h, [ref]$ob) | Out-Null
        $cb = [PWin32]::ClientBox($h)
        # 校正量按客户区目标算，但叠加到外框坐标上（外框=客户区+边框）
        $dx = $Ax - $cb[0]; $dy = $Ay - $cb[1]; $dw = $Aw - $cb[2]; $dh = $Ah - $cb[3]
        if ($dx -ne 0 -or $dy -ne 0 -or $dw -ne 0 -or $dh -ne 0) {
            [PWin32]::SetWindowPos($h, [IntPtr]::Zero, $ob.Left+$dx, $ob.Top+$dy, ($ob.Right-$ob.Left)+$dw, ($ob.Bottom-$ob.Top)+$dh, 0x0004) | Out-Null
            Start-Sleep -Milliseconds 800
            $cb = [PWin32]::ClientBox($h)
        }
        [PWin32]::SetForegroundWindow($h) | Out-Null
        Start-Sleep -Milliseconds 400
        Write-Output ("client: {0},{1} {2}x{3}" -f $cb[0], $cb[1], $cb[2], $cb[3])
    }
    'snap' {
        $p = Get-App
        [PWin32]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 450
        $cb = [PWin32]::ClientBox($p.MainWindowHandle)
        if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
        $bmp = New-Object System.Drawing.Bitmap($cb[2], $cb[3])
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($cb[0], $cb[1], 0, 0, $bmp.Size)
        $path = Join-Path $OutDir "$Name.png"
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        Write-Output "saved: $path ($($cb[2]) x $($cb[3]))"
    }
    'click' {
        # Ax,Ay = 客户区相对像素坐标
        $p = Get-App
        $h = $p.MainWindowHandle
        [PWin32]::SetForegroundWindow($h) | Out-Null
        Start-Sleep -Milliseconds 350
        $cb = [PWin32]::ClientBox($h)
        $x = $cb[0] + $Ax; $y = $cb[1] + $Ay
        [PWin32]::SetCursorPos($x, $y) | Out-Null
        Start-Sleep -Milliseconds 120
        [PWin32]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 90
        [PWin32]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 700
        Write-Output ("clicked: client({0},{1}) screen({2},{3})" -f $Ax, $Ay, $x, $y)
    }
    'wheel' {
      # A = 滚动量（正=向下），在客户区中心滚动
      $p = Get-App
      $h = $p.MainWindowHandle
      [PWin32]::SetForegroundWindow($h) | Out-Null
      Start-Sleep -Milliseconds 300
      $cb = [PWin32]::ClientBox($h)
      $x = $cb[0] + [int]($cb[2] / 2); $y = $cb[1] + [int]($cb[3] / 2)
      [PWin32]::SetCursorPos($x, $y) | Out-Null
      Start-Sleep -Milliseconds 150
      $steps = [Math]::Max(1, [Math]::Abs($Scroll) / 40)
      $dir = if ($Scroll -ge 0) { [uint32]4294967196 } else { [uint32]7864320 }  # -120 / +120
      for ($i = 0; $i -lt $steps; $i++) {
        [PWin32]::mouse_event(0x0800, 0, 0, $dir, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 60
      }
      Start-Sleep -Milliseconds 500
      Write-Output "wheeled $Scroll"
    }
    'ctrlv' {
      # 先确保剪贴板有内容（由外部 Set-Clipboard 设置），再向前台发 Ctrl+V
      Add-Type @'
using System; using System.Runtime.InteropServices;
public class K2 { [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e); }
'@
      [K2]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)  # CTRL down
      Start-Sleep -Milliseconds 60
      [K2]::keybd_event(0x56, 0, 0, [UIntPtr]::Zero)  # V down
      Start-Sleep -Milliseconds 60
      [K2]::keybd_event(0x56, 0, 2, [UIntPtr]::Zero)  # V up
      [K2]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)  # CTRL up
      Start-Sleep -Milliseconds 400
      Write-Output 'ctrl+v sent'
    }
    'close' {
        Stop-Process -Name todo_app -Force -ErrorAction SilentlyContinue
        Write-Output 'closed'
    }
    default { throw "unknown cmd: $Cmd" }
}
