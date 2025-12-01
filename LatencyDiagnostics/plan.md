Quero criar uma ferramenta de diagnóstico de latência em Windows para investigar travamentos de USB, áudio e DPC/ISR (semelhante ao LatencyMon).
O objetivo é:

Gerar snapshots do sistema
– drivers carregados
– dispositivos USB
– dispositivos PCI
– adaptadores de rede
– métricas de CPU
– contadores de DPC/ISR via Performance Counters
– salvar tudo como CSV

Comparar dois snapshots
– identificar drivers adicionados, removidos ou alterados
– identificar diferenças de USB, PCI, rede
– identificar mudanças em DPC/ISR e CPU
– gerar arquivos *-diff.csv
– gerar um summary.csv com total de added/removed/changed por categoria

Gerar uma saída consolidada
– criar um único arquivo .json ou .md com um resumo final:

principais mudanças

drivers suspeitos

picos de ISR/DPC

dispositivos que mudaram estado

mudanças no estado do controlador USB
– essa saída deve ser estruturada para que um LLM possa interpretar posteriormente.
– exemplo: objetos JSON anotados com categoria, gravidade, deltas e caminhos afetados.

Construir um script único
– um comando só deve:

gerar snapshot A

gerar snapshot B

comparar

criar o diff

produzir o JSON final para o LLM
– tudo automatizado.

Preparar terreno para LLM
– a ferramenta deve gerar um arquivo final:
analysis_for_llm.json
– contendo:

lista de alterações relevantes

lista de drivers com mudanças

estatísticas de interrupção

dispositivos envolvidos

possíveis relações causais
– para que o LLM possa gerar um diagnóstico automático.

Preciso que o Copilot gere o script PowerShell completo que:

une o Get-SystemSnapshot.ps1

une o Compare-SystemSnapshots.ps1

adiciona a etapa de consolidação de diff → JSON final

tudo rodando com um único comando.