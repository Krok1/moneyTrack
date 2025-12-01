import os
import requests
import json
from datetime import datetime, timedelta
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from google.genai.errors import APIError
from dotenv import load_dotenv

# Завантажуємо змінні з файлу .env (працює тільки локально!)
load_dotenv() 

# --- КОНФІГУРАЦІЯ ---
# Читаємо ключі зі змінних середовища. Render.com і .env роблять це автоматично.
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")
MONO_TOKEN = os.environ.get("MONO_TOKEN")

# Створюємо клієнта замість configure()
if GEMINI_API_KEY:
    client = genai.Client(api_key=GEMINI_API_KEY)
else:
    client = None

app = FastAPI(title="Budget Core API")

# Налаштування CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], 
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- МОДУЛЬ 1: Банкінг (Monobank) ---
@app.get("/mono-transactions")
async def get_mono_transactions():
    """Отримує виписку за останні 7 днів з Monobank."""
    if not MONO_TOKEN:
        raise HTTPException(status_code=500, detail="MONO_TOKEN не налаштований у змінних середовища.")

    # ... (інша логіка Monobank залишається без змін) ...
    to_time = int(datetime.now().timestamp())
    from_time = int((datetime.now() - timedelta(days=7)).timestamp())
    account = "0" 
    url = f"https://api.monobank.ua/personal/statement/{account}/{from_time}/{to_time}"
    
    headers = {'X-Token': MONO_TOKEN}
    response = requests.get(url, headers=headers)
    
    if response.status_code == 200:
        txs = response.json()
        clean_txs = []
        for t in txs:
            clean_txs.append({
                "id": t['id'],
                "date": datetime.fromtimestamp(t['time']).strftime('%Y-%m-%d %H:%M'),
                "amount": t['amount'] / 100, 
                "description": t['description'],
                "mcc": t['mcc'] 
            })
        return clean_txs
    else:
        raise HTTPException(status_code=response.status_code, detail=response.text)


# --- МОДУЛЬ 2: Сканер Чеків (ШІ) ---
@app.post("/scan-receipt")
async def scan_receipt(file: UploadFile = File(...)):
    if not client: # Перевірка, чи клієнт створений
         raise HTTPException(status_code=500, detail="GEMINI_API_KEY не налаштований.")
    
    if not file.content_type.startswith('image/'):
        raise HTTPException(status_code=400, detail="Потрібне зображення.")

    try:
        image_data = await file.read()
        sample_file = genai.upload_file(file=image_data, display_name=file.filename)
        model = client.models.get('gemini-1.5-flash') # Отримуємо модель через клієнта
        
        prompt = """
        Ти фінансовий асистент. Проаналізуй це фото чека.
        Витягни дані у форматі чистого JSON (без markdown і пояснень):
        {
            "store": "назва магазину",
            "date": "дата у форматі YYYY-MM-DD або DD-MM-YYYY",
            "total_amount": сума числом,
            "currency": "UAH" або "PLN" тощо,
            "items": [
                {"name": "назва товару", "price": ціна товару, "category": "категорія (Їжа, Побут, Техніка)"}
            ]
        }
        Якщо чогось не видно, постав null.
        """
        
        response = model.generate_content([sample_file, prompt])
        genai.delete_file(sample_file.name)

        clean_json = response.text.replace('```json', '').replace('```', '').strip()
        data = json.loads(clean_json)
        return data
    
    except APIError as e:
        raise HTTPException(status_code=500, detail=f"Помилка Gemini API: {e}")
    except json.JSONDecodeError:
        raise HTTPException(status_code=500, detail=f"ШІ повернув невірний JSON: {response.text}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Невідома помилка: {e}")

# Маршрут для перевірки (health check)
@app.get("/")
def read_root():
    return {"status": "ok", "message": "Budget Core API працює!"}