$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$c = $env:VYNIC_SETUP_UI | ConvertFrom-Json
$f = New-Object Windows.Forms.Form
$f.Text = 'Vynic Setup'
$f.ClientSize = New-Object Drawing.Size(600, 300)
$f.StartPosition = 'CenterScreen'
$f.FormBorderStyle = 'FixedDialog'
$f.MaximizeBox = $false
$f.MinimizeBox = $false
$f.Font = New-Object Drawing.Font('Segoe UI', 10)
$l = New-Object Windows.Forms.Label
$l.Location = New-Object Drawing.Point(24, 24)
$l.Size = New-Object Drawing.Size(552, 182)
$l.Text = $c.message
$f.Controls.Add($l)
$script:selected = 0
if ($c.progress) {
  $f.ControlBox = $false
  $bar = New-Object Windows.Forms.ProgressBar
  $bar.Location = New-Object Drawing.Point(24, 236)
  $bar.Size = New-Object Drawing.Size(552, 22)
  $bar.Style = 'Marquee'
  $f.Controls.Add($bar)
  $timer = New-Object Windows.Forms.Timer
  $timer.Interval = 250
  $timer.Add_Tick({
    try {
      $p = Get-Content -LiteralPath $c.progress -Raw -Encoding UTF8 | ConvertFrom-Json
      $l.Text = $p.message
      if ($p.done) { $timer.Stop(); $f.Close() }
    } catch { $l.Text = 'Working. Diagnostics are written to the Vynic setup log.' }
  })
  $timer.Start()
} else {
  $x = 24
  foreach ($choice in $c.buttons) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $choice.text
    $b.Tag = [int]$choice.id
    $b.Location = New-Object Drawing.Point($x, 236)
    $b.Size = New-Object Drawing.Size(132, 38)
    $b.Add_Click({param($sender, $eventArgs) $script:selected = [int]$sender.Tag; $f.Close()})
    $f.Controls.Add($b)
    $x += 142
  }
}
[void]$f.ShowDialog()
if ($timer) { $timer.Dispose() }
$f.Dispose()
Write-Output $script:selected
