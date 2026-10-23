using System;
using System.IO;
using System.Threading.Tasks;
using System.Threading;
using System.Diagnostics;
using Windows.Foundation;
using Windows.Storage.Streams;
public static class CoverReader {
 public static Task<byte[]> ReadAsync(object thumbnail) {
  return Task.Run(()=> {
   var reference=(IRandomAccessStreamReference)thumbnail;
   var opening=reference.OpenReadAsync(); Wait(opening);
   using(var stream=opening.GetResults()) {
    if(stream.Size>16777216) throw new IOException("Cover exceeds 16 MB");
    using(var reader=new DataReader(stream.GetInputStreamAt(0))) {
     var loading=reader.LoadAsync((uint)stream.Size); Wait(loading);
     uint count=loading.GetResults(); var bytes=new byte[count]; reader.ReadBytes(bytes); return bytes;
    }
   }
  });
 }
 static void Wait(IAsyncInfo operation) {
  var watch=Stopwatch.StartNew();
  while(operation.Status==AsyncStatus.Started) {
   if(watch.ElapsedMilliseconds>4500){operation.Cancel();throw new TimeoutException("Cover read timeout");}
   Thread.Sleep(10);
  }
  if(operation.Status==AsyncStatus.Error) throw operation.ErrorCode;
  if(operation.Status==AsyncStatus.Canceled) throw new OperationCanceledException();
 }
}
