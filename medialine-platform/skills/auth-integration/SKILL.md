---
name: auth-integration
description: Authentication and SSO integration patterns for Medialine apps with TaskTool platform
user-invocable: false
---

# Authentication Integration Patterns

Every Medialine app uses a dual-mode authentication system that works both standalone and through TaskTool SSO.

## Architecture

```
Standalone Mode:
  User → App Login Page → Local JWT → App Backend

TaskTool SSO Mode:
  User → TaskTool Login (Entra ID) → Launch App → Token Exchange → App JWT → App Backend

Graph API Access:
  App Backend → TaskTool /api/graph/* → Microsoft Graph API
```

## Backend Auth Integration (FastAPI)

### Dependencies (deps.py)

```python
from typing import Optional
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db

security = HTTPBearer(auto_error=False)

async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: AsyncSession = Depends(get_db)
):
    if not credentials:
        raise HTTPException(status_code=401, detail="Not authenticated")

    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.JWT_SECRET_KEY,
            algorithms=["HS256"]
        )

        # Check token issuer
        issuer = payload.get("iss", "")

        if issuer == "tasktool":
            # Token from TaskTool SSO — trust it
            return await _get_or_create_user_from_tasktool(db, payload)
        else:
            # Local token — validate against local DB
            return await _get_local_user(db, payload.get("sub"))

    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")
```

### Local Auth Endpoints (auth.py)

```python
from fastapi import APIRouter, Depends, HTTPException
from jose import jwt
from datetime import datetime, timedelta

router = APIRouter(prefix="/api/auth", tags=["auth"])

# Dev users — always available
DEV_USERS = {
    "admin": {"password": "Admin123!", "email": "admin@medialine.com", "is_admin": True},
    "testuser": {"password": "Test123!", "email": "test@medialine.com", "is_admin": False},
}

@router.post("/login")
async def login(username: str, password: str):
    if settings.AUTH_MODE == "local":
        user = DEV_USERS.get(username)
        if user and user["password"] == password:
            token = jwt.encode(
                {"sub": username, "email": user["email"], "iss": settings.APP_SLUG,
                 "exp": datetime.utcnow() + timedelta(hours=24)},
                settings.JWT_SECRET_KEY, algorithm="HS256"
            )
            return {"access_token": token, "token_type": "bearer"}
    raise HTTPException(status_code=401, detail="Invalid credentials")

@router.get("/me")
async def me(user = Depends(get_current_user)):
    return {"email": user.email, "display_name": user.display_name, "is_admin": user.is_admin}
```

## Frontend Auth Integration (React)

### Auth Hook (useAuth.tsx)

```typescript
import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import api from '../services/api';

interface User {
  id: string;
  email: string;
  display_name: string;
  is_admin: boolean;
  groups: string[];
}

interface AuthContextType {
  user: User | null;
  isLoading: boolean;
  isTaskToolMode: boolean;
  login: (username: string, password: string) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isTaskToolMode, setIsTaskToolMode] = useState(false);
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();

  useEffect(() => {
    const token = searchParams.get('token');
    if (token) {
      // Launched from TaskTool
      setIsTaskToolMode(true);
      localStorage.setItem('auth_token', token);
      navigate(window.location.pathname, { replace: true });
    }
    fetchUser();
  }, []);

  const fetchUser = async () => {
    try {
      const { data } = await api.get('/api/auth/me');
      setUser(data);
    } catch {
      localStorage.removeItem('auth_token');
    } finally {
      setIsLoading(false);
    }
  };

  const login = async (username: string, password: string) => {
    const { data } = await api.post('/api/auth/login', { username, password });
    localStorage.setItem('auth_token', data.access_token);
    await fetchUser();
  };

  const logout = () => {
    localStorage.removeItem('auth_token');
    setUser(null);
    if (isTaskToolMode) {
      window.location.href = import.meta.env.VITE_TASKTOOL_URL || 'http://localhost:5174';
    }
  };

  return (
    <AuthContext.Provider value={{ user, isLoading, isTaskToolMode, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
};
```

### Axios Instance (api.ts)

```typescript
import axios from 'axios';

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || '',
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('auth_token');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('auth_token');
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);

export default api;
```

## Graph API Access (via TaskTool)

Apps access Microsoft Graph data through TaskTool's centralized proxy:

```python
import httpx
from app.core.config import settings

class GraphClient:
    def __init__(self, user_token: str):
        self.base_url = f"{settings.TASKTOOL_API_URL}/api/graph"
        self.headers = {"Authorization": f"Bearer {user_token}"}

    async def get_manager(self, email: str | None = None) -> dict | None:
        url = f"{self.base_url}/me/manager" if not email else f"{self.base_url}/user/{email}/manager"
        async with httpx.AsyncClient() as client:
            resp = await client.get(url, headers=self.headers)
            return resp.json() if resp.status_code == 200 else None

    async def get_photo(self, email: str | None = None) -> str | None:
        url = f"{self.base_url}/me/photo" if not email else f"{self.base_url}/user/{email}/photo"
        async with httpx.AsyncClient() as client:
            resp = await client.get(url, headers=self.headers)
            return resp.json().get("photo") if resp.status_code == 200 else None
```

## Environment Variables

```bash
# Auth configuration
AUTH_MODE=local                    # local | entra
JWT_SECRET_KEY=dev-secret-key-minimum-32-characters-long
APP_SLUG=my-app                   # Used as JWT issuer

# TaskTool integration
TASKTOOL_API_URL=http://localhost:8004
TASKTOOL_APP_SLUG=my-app

# Entra ID (production only)
ENTRA_TENANT_ID=
ENTRA_CLIENT_ID=
ENTRA_CLIENT_SECRET=
```
