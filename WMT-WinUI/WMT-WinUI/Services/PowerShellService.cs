using System;
using System.Management.Automation;
using System.IO;
using System.Diagnostics;
using System.Collections.Generic;
using System.Linq;

namespace WMT_WinUI;

public class PowerShellService : IDisposable
{
    private bool _disposed = false;
    private readonly string _enginePath;

    public PowerShellService()
    {
        // Try to find the engine module
        var possiblePaths = new[]
        {
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "WMT-Engine.psm1"),
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "WMT-Engine.psm1"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "Windows-Maintenance-Tool", "WMT-WinUI", "WMT-Engine.psm1"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "Windows-Maintenance-Tool", "WMT-Engine.psm1")
        };

        _enginePath = possiblePaths.FirstOrDefault(File.Exists) ?? possiblePaths[0];
    }

    public object? RunEngineScript(string script, params (string Name, object Value)[] parameters)
    {
        if (_disposed) throw new ObjectDisposedException(nameof(PowerShellService));

        using (var ps = PowerShell.Create())
        {
            try
            {
                // Load the engine module
                if (File.Exists(_enginePath))
                {
                    ps.AddScript($"Import-Module -Name '{_enginePath}' -Force -ErrorAction Stop; ");
                }
                else
                {
                    // Fallback: embed minimal functions if engine missing
                    ps.AddScript("function Get-WmtDeviceInfo { return @{ Section = 'Fallback'; OS = @{ Caption = 'Unknown' } } }");
                }

                ps.AddScript(script);
                foreach (var param in parameters)
                {
                    if (param.Value != null)
                        ps.AddParameter(param.Name, param.Value);
                    else
                        ps.AddArgument(param.Value);
                }

                var results = ps.Invoke();
                return results.Count > 0 ? results[0] : null;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[PowerShellService] Script error: {ex.Message}");
                throw new InvalidOperationException($"PowerShell execution failed: {ex.Message}", ex);
            }
        }
    }

    public T? RunEngineScript<T>(string script, params (string Name, object Value)[] parameters) where T : class
    {
        var result = RunEngineScript(script, parameters);
        return result as T;
    }

    public string GetDeviceInfoJson(string section = "All")
    {
        try
        {
            using (var ps = PowerShell.Create())
            {
                if (File.Exists(_enginePath))
                    ps.AddScript($"Import-Module -Name '{_enginePath}' -Force");

                ps.AddScript("Get-WmtDeviceInfo -Section $section | ConvertTo-Json -Depth 10 -Compress");
                ps.AddParameter("section", section);
                var results = ps.Invoke();
                return results.Count > 0 ? results[0]?.ToString() ?? "{}" : "{}";
            }
        }
        catch
        {
            return $"{{ \"Error\": \"Failed to query engine at {_enginePath}\" }}";
        }
    }

    public void RunCleaner(string operation = "Scan")
    {
        try
        {
            using (var ps = PowerShell.Create())
            {
                if (File.Exists(_enginePath))
                    ps.AddScript($"Import-Module -Name '{_enginePath}' -Force");

                ps.AddScript("Invoke-WmtCleanerWorker -Operation $operation");
                ps.AddParameter("operation", operation);
                ps.Invoke();
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[PowerShellService] Cleaner error: {ex.Message}");
        }
    }

    public void InitializeBackgroundManager()
    {
        try
        {
            using (var ps = PowerShell.Create())
            {
                if (File.Exists(_enginePath))
                    ps.AddScript($"Import-Module -Name '{_enginePath}' -Force");
                ps.AddScript("Initialize-WmtBackgroundOperationManager -Log { param($line) [System.Diagnostics.Debug]::WriteLine($line) }");
                ps.Invoke();
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[PowerShellService] Background init error: {ex.Message}");
        }
    }

    public void Dispose()
    {
        _disposed = true;
    }
}
