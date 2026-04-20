$targets = @(
    'https://kushnir.cloud/static/css/main.c5955fd3.css',
    'https://kushnir.cloud/',
    'https://ide.kushnir.cloud/'
)

function Invoke-Burst {
    param(
        [string]$Url,
        [int]$Count = 5,
        [int]$Throttle = 5
    )

    $results = 1..$Count | ForEach-Object -Parallel {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $code = & curl.exe -sk -o NUL -w '%{http_code}' $using:Url 2>$null
        $sw.Stop()
        [pscustomobject]@{
            Status = $code
            Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 3)
        }
    } -ThrottleLimit $Throttle

    [pscustomobject]@{
        Url = $Url
        Count = $results.Count
        StatusSummary = ($results | Group-Object Status | Sort-Object Name | ForEach-Object { "Status $($_.Name): $($_.Count)" }) -join '; '
        Avg = [math]::Round((($results | Measure-Object Seconds -Average).Average), 3)
        Min = [math]::Round((($results | Measure-Object Seconds -Minimum).Minimum), 3)
        Max = [math]::Round((($results | Measure-Object Seconds -Maximum).Maximum), 3)
    }
}

$results = foreach ($target in $targets) {
    Invoke-Burst -Url $target
}

foreach ($result in $results) {
    'Target: ' + $result.Url
    'Requests: ' + $result.Count + ' | Parallel: 5'
    'Status summary: ' + $result.StatusSummary
    'Avg time: ' + $result.Avg + ' s'
    'Min time: ' + $result.Min + ' s'
    'Max time: ' + $result.Max + ' s'
    ''
}
