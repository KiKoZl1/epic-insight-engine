import { useState, useCallback, useRef } from 'react';
import { Upload, FileArchive, CheckCircle2, AlertTriangle, XCircle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Progress } from '@/components/ui/progress';
import { Card, CardContent } from '@/components/ui/card';
import { processZipFile, type ProcessingResult, type ProcessingLog } from '@/lib/parsing/zipProcessor';
import { calculateMetrics, type MetricsResult } from '@/lib/parsing/metricsEngine';

interface ZipUploaderProps {
  onComplete: (result: ProcessingResult, metrics: MetricsResult) => void;
  disabled?: boolean;
}

export default function ZipUploader({ onComplete, disabled }: ZipUploaderProps) {
  const [dragOver, setDragOver] = useState(false);
  const [processing, setProcessing] = useState(false);
  const [progress, setProgress] = useState(0);
  const [progressMsg, setProgressMsg] = useState('');
  const [logs, setLogs] = useState<ProcessingLog[]>([]);
  const fileRef = useRef<HTMLInputElement>(null);

  const handleFile = useCallback(async (file: File) => {
    if (!file.name.toLowerCase().endsWith('.zip')) {
      setLogs([{ type: 'error', message: 'Apenas arquivos .zip são aceitos.' }]);
      return;
    }

    setProcessing(true);
    setLogs([]);
    setProgress(0);

    try {
      const result = await processZipFile(file, (pct, msg) => {
        setProgress(pct);
        setProgressMsg(msg);
      });

      setLogs(result.logs);

      if (Object.keys(result.datasets).length === 0) {
        setProcessing(false);
        return;
      }

      const metrics = calculateMetrics(result.datasets);
      onComplete(result, metrics);
    } catch (err) {
      setLogs(prev => [...prev, {
        type: 'error' as const,
        message: `Erro inesperado: ${err instanceof Error ? err.message : 'desconhecido'}`,
      }]);
    } finally {
      setProcessing(false);
    }
  }, [onComplete]);

  const onDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setDragOver(false);
    const file = e.dataTransfer.files[0];
    if (file) handleFile(file);
  }, [handleFile]);

  const onFileChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) handleFile(file);
  }, [handleFile]);

  const logIcon = (type: ProcessingLog['type']) => {
    switch (type) {
      case 'info': return <CheckCircle2 className="h-3.5 w-3.5 text-emerald-500 shrink-0" />;
      case 'warning': return <AlertTriangle className="h-3.5 w-3.5 text-amber-500 shrink-0" />;
      case 'error': return <XCircle className="h-3.5 w-3.5 text-red-500 shrink-0" />;
    }
  };

  return (
    <div className="space-y-4">
      <div
        onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
        onDragLeave={() => setDragOver(false)}
        onDrop={onDrop}
        onClick={() => !processing && !disabled && fileRef.current?.click()}
        className={`
          relative rounded-xl border-2 border-dashed p-10 text-center transition-all cursor-pointer
          ${dragOver ? 'border-primary bg-primary/5 scale-[1.01]' : 'border-muted-foreground/20 hover:border-primary/50'}
          ${processing || disabled ? 'opacity-60 pointer-events-none' : ''}
        `}
      >
        <input
          ref={fileRef}
          type="file"
          accept=".zip"
          className="hidden"
          onChange={onFileChange}
          disabled={processing || disabled}
        />

        {processing ? (
          <div className="space-y-4">
            <Loader2 className="h-10 w-10 mx-auto text-primary animate-spin" />
            <p className="text-sm font-medium">{progressMsg}</p>
            <Progress value={progress} className="max-w-xs mx-auto" />
          </div>
        ) : (
          <>
            <FileArchive className="h-10 w-10 mx-auto text-muted-foreground mb-3" />
            <p className="font-display font-semibold text-lg mb-1">
              Arraste o ZIP aqui
            </p>
            <p className="text-sm text-muted-foreground mb-4">
              ou clique para selecionar o export do painel da Epic
            </p>
            <Button variant="outline" size="sm" type="button">
              <Upload className="h-4 w-4 mr-2" /> Escolher Arquivo
            </Button>
          </>
        )}
      </div>

      {logs.length > 0 && (
        <Card>
          <CardContent className="p-4">
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">
              Log de Processamento
            </p>
            <div className="space-y-1 max-h-48 overflow-y-auto text-xs">
              {logs.map((log, i) => (
                <div key={i} className="flex items-start gap-2">
                  {logIcon(log.type)}
                  <span className={log.type === 'error' ? 'text-red-500' : ''}>{log.message}</span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
