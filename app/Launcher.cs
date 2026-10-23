using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
[assembly: System.Reflection.AssemblyTitle("浮音 · Luma")]
[assembly: System.Reflection.AssemblyProduct("浮音 · Luma")]
[assembly: System.Reflection.AssemblyDescription("Floating desktop lyrics")]
[assembly: System.Reflection.AssemblyVersion("1.31.0.0")]
class Launcher {
 [STAThread] static void Main(string[] args) {
  string script=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Luma.ps1");
  if(!File.Exists(script)){MessageBox.Show("Please keep Luma.exe beside Luma.ps1.","Luma Lyrics");return;}
  string shell=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),@"System32\WindowsPowerShell\v1.0\powershell.exe");
  var start=new ProcessStartInfo(shell,"-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \""+script+"\""+(Array.IndexOf(args,"--demo")>=0?" -Demo":"")+(Array.IndexOf(args,"--startup")>=0?" -Startup":""));
  start.UseShellExecute=false;start.CreateNoWindow=true;start.WorkingDirectory=AppDomain.CurrentDomain.BaseDirectory;
  Process.Start(start);
 }
}
