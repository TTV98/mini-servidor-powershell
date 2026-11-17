# Mini servidor local em PowerShell

Um servidor web pequeno, num arquivo só, que roda no próprio computador com o PowerShell que já vem no Windows. Ele mostra uma página HTML e deixa essa página **salvar e ler arquivos JSON** numa pasta escolhida. Não precisa instalar nada.

> **Exemplo didático, escrito para este repositório.** Não é o código de nenhuma ferramenta de empresa. A página de exemplo é um bloco de anotações. Não guarde dados pessoais nela.

## Por que um servidor local

Uma página HTML aberta com clique duplo (endereço `file://`) não consegue gravar arquivos no computador. Ela também não carrega módulos JavaScript (`import`). Por segurança, o navegador bloqueia as duas coisas.

Com um servidor local, a página passa a abrir em `http://localhost` e pode pedir ao servidor: "salve este conteúdo". Quem grava o arquivo é o servidor, e só onde ele permite.

## O que tem aqui

| Arquivo | O que é |
|---|---|
| [`servidor.ps1`](servidor.ps1) | O servidor, com comentários em português |
| [`iniciar.bat`](iniciar.bat) | Abre o servidor e o navegador com clique duplo |
| [`site/index.html`](site/index.html) | Página de exemplo: um bloco de anotações que salva e carrega |
| [`dados/`](dados/LEIA-ME.txt) | Onde os arquivos são salvos. Vai vazia para o GitHub |
| [`testes/testar.ps1`](testes/testar.ps1) | 34 testes automáticos |

## Como usar

1. Baixe o repositório (botão **Code** e depois **Download ZIP**) e descompacte.
2. **Leia o `servidor.ps1` antes de rodar.** Vale para qualquer script baixado da internet.
3. Dê clique duplo no `iniciar.bat`. O servidor abre em `http://localhost:8090/` e o navegador abre na página.
4. Escreva algo, clique em **Salvar** e depois em **Carregar**.
5. Para parar, aperte **Ctrl+C** na janela preta ou feche a janela.

O `iniciar.bat` usa `-ExecutionPolicy Bypass`, que vale **só para essa execução** e não muda a configuração do Windows. Se o Windows bloquear o arquivo por ter vindo da internet, clique com o botão direito, vá em **Propriedades** e marque **Desbloquear**.

Para rodar em outra porta ou com outra pasta de dados:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File servidor.ps1 -Porta 8095 -PastaDados C:\temp\meus-dados
```

## Os endereços do servidor

| Pedido | O que faz |
|---|---|
| `GET /` e outros arquivos | Mostra os arquivos da pasta `site` (só `.html`, `.css`, `.js`, `.json`, `.png`, `.svg` e `.ico`) |
| `GET /api/ping` | Responde `{"ok":true}`. Serve para saber se o servidor está aberto |
| `GET /api/listar` | Lista os arquivos `.json` da pasta `dados` |
| `GET /api/ler?nome=anotacoes.json` | Devolve o conteúdo do arquivo |
| `POST /api/salvar?nome=anotacoes.json` | Salva o conteúdo enviado (JSON) |

## As proteções, e por que cada uma existe

| Proteção | Contra o quê |
|---|---|
| Escuta só em `localhost` e recusa pedidos que não vêm do próprio computador | Acesso por outro computador da rede |
| Só grava na pasta `dados` | Nenhum pedido consegue gravar em outra pasta |
| Nome de arquivo só com letras minúsculas, números e hífen, terminando em `.json` | Nomes como `..\..\Windows\algo` |
| A função `DentroDaPasta` confere se o arquivo pedido fica dentro da pasta `site` | Ler arquivos de fora, como o próprio `servidor.ps1` |
| Só aceita conteúdo `application/json` e recusa a origem de outro site | Outro site aberto no navegador mandar salvar algo aqui |
| Limite de tamanho (1 MB) | Um envio enorme encher o disco |
| Confere se o JSON é válido antes de gravar | Gravar um arquivo quebrado |
| Guarda a versão anterior em `dados\versoes-anteriores` antes de sobrescrever | Perder o que estava salvo |
| Grava num arquivo temporário e só depois troca | O arquivo ficar pela metade se algo falhar no meio |
| Erros vão para `servidor-erros.log` | Um erro sumir sem ninguém saber |

Isto é um exemplo para estudo e para uso pessoal, no próprio computador. Não é um servidor para colocar na internet.

## O que foi testado

Em 17/11/2026, no Windows 10 com o Windows PowerShell 5.1:

- **Os 34 testes do `testes/testar.ps1` passaram.** Eles abrem o servidor numa porta de teste, com uma pasta temporária, e conferem: salvar com acentos, guardar a versão anterior, ler, listar, recusar nomes inválidos, JSON inválido, outro tipo de conteúdo, outra origem e conteúdo acima do limite, além dos códigos 404 e 405.
- **Tentativas de sair da pasta `site`** (`/../servidor.ps1`, `%2e%2e`, `%5c`): o próprio Windows (HTTP.sys) já recusa esses endereços com 403, antes de chegarem ao script. Por isso, a função `DentroDaPasta` também é testada sozinha, com 7 casos.
- **A página de exemplo** foi usada no navegador do Claude Code (Chromium): salvar, salvar de novo (a versão anterior foi guardada), apagar o texto e carregar. Os acentos voltaram certos e o console não mostrou erros.

**Não testado:** o clique duplo no `iniciar.bat`, o Ctrl+C para parar, o PowerShell 7 e o Windows 11.

Para rodar os testes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File testes\testar.ps1
```

## Ferramentas usadas

- Windows PowerShell 5.1 e a classe `HttpListener` do .NET, que já vêm no Windows.
- HTML, CSS e JavaScript puro na página de exemplo.
- Usei IA como apoio ([Claude Code](https://claude.com/claude-code)): eu defini as regras e as proteções, conferi os testes e revisei.

## Licença

Código sob a [licença MIT](LICENSE): pode usar, mudar e distribuir, mantendo o aviso de direitos autorais.

## Autor

**Lucas Terto**: [LinkedIn](https://www.linkedin.com/in/soulucas1212) · [outros repositórios](https://github.com/TTV98)
