using System;
using System.Runtime.InteropServices;
public static class GlassNative {
 [StructLayout(LayoutKind.Sequential)] struct Accent { public int State, Flags, Color, Animation; }
 [StructLayout(LayoutKind.Sequential)] struct Data { public int Attribute; public IntPtr Pointer; public int Size; }
 [StructLayout(LayoutKind.Sequential)] struct Margins { public int Left, Right, Top, Bottom; }
 [DllImport("user32.dll")] static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref Data data);
 [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
 [DllImport("dwmapi.dll")] static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref Margins margins);
 [DllImport("gdi32.dll")] static extern IntPtr CreateRoundRectRgn(int left,int top,int right,int bottom,int width,int height);
 [DllImport("user32.dll")] static extern int SetWindowRgn(IntPtr hwnd,IntPtr region,bool redraw);
 [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
 public static string Apply(IntPtr hwnd, int width, int height, int radius, bool acrylic, uint tint) {
  var m = new Margins { Left=-1, Right=-1, Top=-1, Bottom=-1 }; DwmExtendFrameIntoClientArea(hwnd,ref m);
  // Accent acrylic samples the actual content behind the window. The WPF overlay
  // owns tint strength; avoid stacking an opaque system-material tint under it.
  int backdrop=1;
  int systemResult=DwmSetWindowAttribute(hwnd,38,ref backdrop,4);
  var a=new Accent {State=acrylic?4:0, Flags=0, Color=unchecked((int)((tint & 0x00FFFFFFu) | 0x10000000u))};
  int accentResult=0;
  IntPtr p=Marshal.AllocHGlobal(Marshal.SizeOf(a));
  try { Marshal.StructureToPtr(a,p,false); var d=new Data{Attribute=19,Pointer=p,Size=Marshal.SizeOf(a)}; accentResult=SetWindowCompositionAttribute(hwnd,ref d); }
  finally {Marshal.FreeHGlobal(p);}
  if(acrylic && accentResult==0){backdrop=3;systemResult=DwmSetWindowAttribute(hwnd,38,ref backdrop,4);}
  int noBorder=unchecked((int)0xFFFFFFFE); DwmSetWindowAttribute(hwnd,34,ref noBorder,4);
  int corner=2; int cornerResult=DwmSetWindowAttribute(hwnd,33,ref corner,4);
  // A custom window region disables DWM's native rounded-corner/backdrop treatment.
  if(cornerResult!=0){IntPtr r=CreateRoundRectRgn(0,0,width+1,height+1,radius,radius); if(SetWindowRgn(hwnd,r,true)==0) DeleteObject(r);}
  else {SetWindowRgn(hwnd,IntPtr.Zero,true);}
  if(!acrylic)return "Off";
  if(accentResult!=0)return "BackdropAcrylic";
  return systemResult==0?"SystemAcrylicFallback":"Unavailable";
 }
}
