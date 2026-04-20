$url = 'https://kushnir.cloud/static/css/main.c5955fd3.css'
$results = 1..15 | ForEach-Object -Parallel {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $code = & curl.exe -sk -o NUL -w '%{http_code}' $using:url 2>$null
    $sw.Stop()
    [pscustomobject]@{
        Status = $code
        Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 3)
    }
} -ThrottleLimit 5

'Target: ' + $url
'Requests: ' + $results.Count + ' | Parallel: 5'
$results | Sort-Object Seconds | Format-Table -AutoSize
$groups = $results | Group-Object Status | Sort-Object Name
foreach ($group in $groups) {
    'Status ' + $group.Name + ': ' + $group.Count
}
$metrics = $results | Measure-Object Seconds -Average -Minimum -Maximum
'Avg time: ' + [math]::Round($metrics.Average, 3) + ' s'
'Min time: ' + [math]::Round($metrics.Minimum, 3) + ' s'
'Max time: ' + [math]::Round($metrics.Maximum, 3) + ' s'
