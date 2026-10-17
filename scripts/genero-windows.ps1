# Escribe SOLO el genero (System.Music.Genre) usando el sistema de propiedades de Windows,
# igual que Explorador > Propiedades > Detalles. Uso: genero-windows.ps1 -Archivo x.m4a -Generos "Rock","Pop"
param([Parameter(Mandatory)][string]$Archivo, [Parameter(Mandatory)][string]$Generos)  # separados por ;
if (-not ('PropTool' -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class PropTool {
    [StructLayout(LayoutKind.Sequential, Pack = 4)] public struct PROPERTYKEY { public Guid fmtid; public uint pid; }
    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        [PreserveSig] int GetCount(out uint c);
        [PreserveSig] int GetAt(uint i, out PROPERTYKEY k);
        [PreserveSig] int GetValue(ref PROPERTYKEY k, IntPtr pv);
        [PreserveSig] int SetValue(ref PROPERTYKEY k, IntPtr pv);
        [PreserveSig] int Commit();
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SHGetPropertyStoreFromParsingName(string path, IntPtr pbc, int flags, ref Guid iid, out IPropertyStore store);
    [DllImport("propsys.dll", CharSet = CharSet.Unicode)] static extern int InitPropVariantFromStringVector(string[] v, uint n, IntPtr pv);
    [DllImport("ole32.dll")] static extern int PropVariantClear(IntPtr pv);
    public static void SetGenre(string path, string[] genres) {
        Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"); IPropertyStore st;
        int hr = SHGetPropertyStoreFromParsingName(path, IntPtr.Zero, 2 /*GPS_READWRITE*/, ref iid, out st); Marshal.ThrowExceptionForHR(hr);
        PROPERTYKEY key = new PROPERTYKEY { fmtid = new Guid("56A3372E-CE9C-11D2-9F0E-006097C686F6"), pid = 11 }; // System.Music.Genre
        IntPtr pv = Marshal.AllocCoTaskMem(24);
        try {
            for (int i = 0; i < 24; i++) Marshal.WriteByte(pv, i, 0);
            Marshal.ThrowExceptionForHR(InitPropVariantFromStringVector(genres, (uint)genres.Length, pv));
            Marshal.ThrowExceptionForHR(st.SetValue(ref key, pv));
            Marshal.ThrowExceptionForHR(st.Commit());
        } finally { PropVariantClear(pv); Marshal.FreeCoTaskMem(pv); Marshal.ReleaseComObject(st); }
    }
}
'@
}
[PropTool]::SetGenre((Resolve-Path -LiteralPath $Archivo).Path, [string[]]@((($Generos -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join '; ')))
