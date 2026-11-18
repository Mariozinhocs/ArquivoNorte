using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

class Program {
    [DllImport("shell32.dll", SetLastError = true)]
    public static extern void SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);

    [STAThread]
    static int Main(string[] args) {
        try {
            // Define identidade exclusiva na barra de tarefas do Windows
            SetCurrentProcessExplicitAppUserModelID("ArquivoNorte.BuscaCorporativa.v2");

            string appDir = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(appDir, "Buscar-CCC.ps1");

            if (!File.Exists(scriptPath)) {
                System.Windows.Forms.MessageBox.Show(
                    "Arquivo principal do sistema (Buscar-CCC.ps1) não encontrado no diretório:\n" + appDir,
                    "ArquivoNorte - Erro",
                    System.Windows.Forms.MessageBoxButtons.OK,
                    System.Windows.Forms.MessageBoxIcon.Error
                );
                return 1;
            }

            string scriptContent = File.ReadAllText(scriptPath);

            var initialSessionState = InitialSessionState.CreateDefault();
            initialSessionState.ApartmentState = System.Threading.ApartmentState.STA;
            initialSessionState.ThreadOptions = PSThreadOptions.UseCurrentThread;

            using (Runspace runspace = RunspaceFactory.CreateRunspace(initialSessionState)) {
                runspace.Open();
                using (PowerShell ps = PowerShell.Create()) {
                    ps.Runspace = runspace;
                    ps.AddScript(scriptContent);

                    if (args != null && args.Length > 0) {
                        for (int i = 0; i < args.Length; i++) {
                            ps.AddArgument(args[i]);
                        }
                    }

                    ps.Invoke();
                }
            }
            return 0;
        } catch (Exception ex) {
            System.Windows.Forms.MessageBox.Show(
                "Erro ao inicializar o ArquivoNorte:\n" + ex.Message,
                "ArquivoNorte - Erro",
                System.Windows.Forms.MessageBoxButtons.OK,
                System.Windows.Forms.MessageBoxIcon.Error
            );
            return 1;
        }
    }
}
