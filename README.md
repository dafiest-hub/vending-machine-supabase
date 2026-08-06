# Vending Machine Supabase Backend & MQTT Consumer

Este repositorio contiene la arquitectura de la base de datos en **Supabase (PostgreSQL)** y el servicio **MQTT Consumer** en Node.js para recibir, procesar y almacenar eficientemente la información generada por las máquinas expendedoras de productos de limpieza (Firmware ESP32 con Zephyr RTOS).

**Autor:** acovarrubiasd2500 (`acovarrubiasd2500@alumno.ipn.mx`)

---

## 📁 Estructura del Repositorio

- `schema.sql`: Script DDL SQL completo para crear la base de datos en Supabase (Tablas, Tipos ENUM, Vistas Mensuales, Índices y Políticas RLS).
- `consumer.js`: Servicio en Node.js que se suscribe a los tópicos MQTT del broker e inserta los eventos en Supabase.
- `package.json`: Manifiesto de dependencias de Node.js (`mqtt`, `@supabase/supabase-js`, `dotenv`).
- `.env.example`: Plantilla de variables de entorno requeridas para el Consumer.

---

## 🚀 Guía de Despliegue en Supabase

### 1. Configuración del Esquema de Base de Datos
1. Entra a tu panel de control en [Supabase](https://supabase.com/).
2. Crea un nuevo proyecto o selecciona uno existente.
3. Dirígete a la sección **SQL Editor**.
4. Copia y pega todo el contenido de `schema.sql` y ejecuta la consulta (**Run**).

### 2. Configuración del Servicio Consumer MQTT
1. Clona este repositorio o entra al directorio del proyecto.
2. Instala las dependencias:
   ```bash
   npm install
   ```
3. Crea tu archivo `.env` a partir de la plantilla:
   ```bash
   cp .env.example .env
   ```
4. Configura tus credenciales en `.env`:
   - `SUPABASE_URL`: La URL de tu proyecto en Supabase (Project Settings -> API).
   - `SUPABASE_SERVICE_ROLE_KEY`: La clave secreta de rol de servicio (`service_role` secret) para permitir inserciones automáticas por el consumer.
   - `MQTT_BROKER_HOST`: Host de tu broker MQTT (ejemplo: `broker.hivemq.com`).
   - `MQTT_TOPIC_PREFIX`: Prefijo de tópicos (por defecto `vending`). Esto aísla los mensajes de tus máquinas para evitar interferencias de otros usuarios si usas un broker público.

5. Inicia el servicio consumer:
   ```bash
   npm start
   ```

---

## 📊 Tablas y Vistas Incluidas en Supabase

### Tablas Principales
- `machines`: Registro de máquinas expendedoras y posición GPS.
- `products`: Catálogo general de productos de limpieza.
- `machine_tanks`: Estado e inventario actual de los 8 tanques por máquina.
- `sale_incomes`: Registro de dinero ingresado por cada compra concretada (monedas, efectivo, tarjeta).
- `sales`: Registro de ventas históricas, litros pedidos vs. litros medidos por el sensor de flujo.
- `money_collections`: Historial de cortes de caja y retiros de efectivo por técnicos.
- `tank_operations`: Historial de recargas de insumos (`refill`) y purgas (`purge`).
- `system_alerts`: Registro de violaciones de seguridad (`coinbox_tampered`), inclinación y fallas.
- `machine_status`: Snapshot instantáneo de la máquina, incluyendo el **saldo disponible sin reclamar** (`available_balance`).

### Vistas SQL (Filtros y Métricas Mensuales)
- `v_monthly_sales_report`: Resumen mensual de ventas, ingresos brutos y litros por máquina.
- `v_monthly_product_performance`: Productos más vendidos agrupados por mes.
- `v_monthly_revenue_by_payment_type`: Desglose mensual de ingresos por método de pago.
- `v_monthly_financial_audit`: Auditoría y conciliación mensual de caja (ventas vs. recaudado).
- `v_monthly_tank_operations`: Volumen mensual de insumos recargados/purgados.
