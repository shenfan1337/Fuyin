using System;
using System.IO;
using System.IO.Compression;
using System.Text;

// KRC lyric container reader. Only returns UTF-8 text; never executes content.
public static class KrcReader {
 public static string Read(string content) {
  byte[] bytes=Convert.FromBase64String(content);
  if(bytes.Length<10 || bytes.Length>2097152 || Encoding.ASCII.GetString(bytes,0,4)!="krc1")
   throw new InvalidDataException("Invalid KRC lyric header");
  byte[] key={64,71,97,119,94,50,116,71,81,54,49,45,206,210,110,105};
  for(int i=4;i<bytes.Length;i++) bytes[i]^=key[(i-4)%key.Length];
  using(var input=new MemoryStream(bytes,6,bytes.Length-10))
  using(var deflate=new DeflateStream(input,CompressionMode.Decompress))
  using(var output=new MemoryStream()) {
   byte[] buffer=new byte[4096];int count;
   while((count=deflate.Read(buffer,0,buffer.Length))>0) {
    if(output.Length+count>2097152) throw new InvalidDataException("KRC lyric size limit");
    output.Write(buffer,0,count);
   }
   return new UTF8Encoding(false,true).GetString(output.ToArray()).TrimStart('\uFEFF');
  }
 }
}
