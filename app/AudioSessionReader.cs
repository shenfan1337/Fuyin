using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class AudioSessionReader {
 // Read session activity by default. Optional metering returns only a peak
 // level; the caller filters rests and delayed timeline/status notifications.
 // No audio samples, mixer changes, or player control are performed here.
 [ComImport,Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class Enumerator {}
 [ComImport,Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IDevices {
  [PreserveSig] int EnumAudioEndpoints(int flow,int mask,out ICollection devices);
  [PreserveSig] int GetDefaultAudioEndpoint(int flow,int role,out IDevice device);
 }
 [ComImport,Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface ICollection {[PreserveSig] int GetCount(out uint n);[PreserveSig] int Item(uint n,out IDevice d);}
 [ComImport,Guid("D666063F-1587-4E43-81F1-B948E807363F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IDevice {
  [PreserveSig] int Activate(ref Guid iid,int context,IntPtr parameters,[MarshalAs(UnmanagedType.IUnknown)] out object obj);
 }
 [ComImport,Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IManager {
  [PreserveSig] int GetAudioSessionControl(IntPtr guid,uint flags,out IntPtr control);
  [PreserveSig] int GetSimpleAudioVolume(IntPtr guid,uint flags,out IntPtr volume);
  [PreserveSig] int GetSessionEnumerator(out ISessions sessions);
 }
 [ComImport,Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface ISessions {
  [PreserveSig] int GetCount(out int count);
  [PreserveSig] int GetSession(int index,out IControl session);
 }
 [ComImport,Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IControl {
  [PreserveSig] int GetState(out int state);
  [PreserveSig] int GetDisplayName(out IntPtr name);
  [PreserveSig] int SetDisplayName(IntPtr name,IntPtr context);
  [PreserveSig] int GetIconPath(out IntPtr name);
  [PreserveSig] int SetIconPath(IntPtr name,IntPtr context);
  [PreserveSig] int GetGroupingParam(out Guid g);
  [PreserveSig] int SetGroupingParam(ref Guid g,IntPtr context);
  [PreserveSig] int RegisterAudioSessionNotification(IntPtr c);
  [PreserveSig] int UnregisterAudioSessionNotification(IntPtr c);
  [PreserveSig] int GetSessionIdentifier(out IntPtr id);
  [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr id);
  [PreserveSig] int GetProcessId(out uint pid);
 }
 [ComImport,Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IMeter {
  [PreserveSig] int GetPeakValue(out float peak);
 }
 public sealed class Sample {public uint Pid;public int State;public float Peak=-1;}
 public static Sample[] Read() {return Read(false);}
 public static Sample[] Read(bool includePeak) {
  var results=new List<Sample>();var enumerator=(IDevices)new Enumerator();ICollection devices=null;
  try {
   Marshal.ThrowExceptionForHR(enumerator.EnumAudioEndpoints(0,1,out devices));uint n;Marshal.ThrowExceptionForHR(devices.GetCount(out n));
   for(uint d=0;d<n;d++){
    IDevice device=null;object managerObject=null;ISessions sessions=null;
    try{
     Marshal.ThrowExceptionForHR(devices.Item(d,out device));var iid=typeof(IManager).GUID;
     Marshal.ThrowExceptionForHR(device.Activate(ref iid,23,IntPtr.Zero,out managerObject));
     Marshal.ThrowExceptionForHR(((IManager)managerObject).GetSessionEnumerator(out sessions));int count;Marshal.ThrowExceptionForHR(sessions.GetCount(out count));
     for(int i=0;i<count;i++){
      IControl control=null;
      try{if(sessions.GetSession(i,out control)<0)continue;uint pid;int state;if(control.GetProcessId(out pid)>=0&&control.GetState(out state)>=0){float peak=-1;if(includePeak){try{((IMeter)control).GetPeakValue(out peak);}catch(COMException){}catch(InvalidCastException){}}results.Add(new Sample{Pid=pid,State=state,Peak=peak});}}
      finally{if(control!=null)Marshal.ReleaseComObject(control);}
     }
    }finally{if(sessions!=null)Marshal.ReleaseComObject(sessions);if(managerObject!=null)Marshal.ReleaseComObject(managerObject);if(device!=null)Marshal.ReleaseComObject(device);}
   }
  }finally{if(devices!=null)Marshal.ReleaseComObject(devices);Marshal.ReleaseComObject(enumerator);}
  return results.ToArray();
 }
}
