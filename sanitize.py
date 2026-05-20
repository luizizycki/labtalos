import re

def sanitize(filepath, outpath):
    try:
        with open(filepath, "r") as f:
            content = f.read()

        # Substituir tokens e chaves criptográficas
        content = re.sub(r"(token:\s+)[a-zA-Z0-9\.]+", r"\1${TALOS_TOKEN}", content)
        content = re.sub(r"(secretboxEncryptionSecret:\s+)[^\n]+", r"\1${SECRETBOX_KEY}", content)
        content = re.sub(r"(crt:\s+)[a-zA-Z0-9+/=\n]+", r"\1${CA_CRT}\n", content)
        content = re.sub(r"(key:\s+)[a-zA-Z0-9+/=\n]+", r"\1${CA_KEY}\n", content)
        content = re.sub(r"(id:\s+)[a-zA-Z0-9]+", r"\1${CLUSTER_ID}", content)
        content = re.sub(r"(secret:\s+)[a-zA-Z0-9]+", r"\1${CLUSTER_SECRET}", content)
        content = re.sub(r"(aescbcEncryptionKey:\s+)[^\n]+", r"\1${AES_KEY}", content)
        
        # Substituir IPs hardcoded para template
        content = re.sub(r"192\.168\.1\.50", r"${CONTROL_PLANE_IP}", content)
        content = re.sub(r"192\.168\.1\.51", r"${WORKER_IP}", content)
        content = re.sub(r"192\.168\.1\.221-192\.168\.1\.229", r"${METALLB_IP_RANGE}", content)

        with open(outpath, "w") as f:
            f.write(content)
        print(f"✅ Arquivo {outpath} gerado com sucesso!")
    except FileNotFoundError:
        print(f"⚠️ Arquivo {filepath} não encontrado, pulando...")

sanitize("controlplane.yaml", "controlplane.template.yaml")
sanitize("worker.yaml", "worker.template.yaml")
sanitize("metallb-l2-config.yaml", "metallb-l2-config.template.yaml")
