-- ============================================================================
-- BASE DE DATOS EN SUPABASE PARA SISTEMA DE VENDING MACHINES DE LIMPIEZA
-- Proyecto: SW-VENDING_MACHINE-ESP32-ZEPHYR Backend & Supabase
-- Autor: acovarrubiasd2500@alumno.ipn.mx
-- ============================================================================

-- Habilitar extensión UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ----------------------------------------------------------------------------
-- 1. TIPOS ENUM (ROLES DE PWA, MÉTODOS DE PAGO, ESTADOS Y CATEGORÍAS)
-- ----------------------------------------------------------------------------
CREATE TYPE user_role_enum AS ENUM ('admin', 'technician', 'viewer');
CREATE TYPE payment_type_enum AS ENUM ('monedas', 'efectivo', 'tarjeta');
CREATE TYPE machine_operating_status AS ENUM ('online', 'offline', 'maintenance', 'security_lock');
CREATE TYPE purchase_status_enum AS ENUM ('success', 'fail');
CREATE TYPE tank_action_enum AS ENUM ('sale', 'refill', 'purge');
CREATE TYPE collection_status_enum AS ENUM ('success', 'fail');
CREATE TYPE alert_category_enum AS ENUM ('security', 'pump', 'sales', 'stock', 'module');

-- ----------------------------------------------------------------------------
-- 2. TABLA: PERFILES DE USUARIOS PWA (public.profiles)
-- ----------------------------------------------------------------------------
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL UNIQUE,
    full_name VARCHAR(150),
    avatar_url TEXT,
    role user_role_enum NOT NULL DEFAULT 'viewer',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 3. TABLA: MÁQUINAS EXPENDEDORAS (machines)
-- ----------------------------------------------------------------------------
CREATE TABLE machines (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id VARCHAR(32) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    location_address TEXT,
    latitude NUMERIC(10, 8),
    longitude NUMERIC(11, 8),
    status machine_operating_status DEFAULT 'online',
    firmware_version VARCHAR(20) DEFAULT '2.0.0',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 4. TABLA: CATÁLOGO DE PRODUCTOS (products)
-- ----------------------------------------------------------------------------
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    default_price_per_liter NUMERIC(10, 2) NOT NULL CHECK (default_price_per_liter >= 0),
    density_kg_m3 NUMERIC(8, 2) DEFAULT 1000.0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 5. TABLA: CONFIGURACIÓN Y ESTADO DE TANQUES (machine_tanks)
-- ----------------------------------------------------------------------------
CREATE TABLE machine_tanks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    machine_id UUID NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
    tank_number SMALLINT NOT NULL CHECK (tank_number BETWEEN 1 AND 8),
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    price_per_liter NUMERIC(10, 2) NOT NULL CHECK (price_per_liter >= 0),
    capacity_liters NUMERIC(8, 3) NOT NULL CHECK (capacity_liters > 0),
    current_liters NUMERIC(8, 3) NOT NULL DEFAULT 0.0 CHECK (current_liters >= 0),
    current_percentage NUMERIC(5, 2) GENERATED ALWAYS AS (
        ROUND((current_liters / NULLIF(capacity_liters, 0)) * 100, 2)
    ) STORED,
    low_threshold_liters NUMERIC(8, 3) NOT NULL DEFAULT 3.0,
    is_above_minimum BOOLEAN DEFAULT true,
    is_pump_working BOOLEAN DEFAULT true,
    last_refill_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_machine_tank UNIQUE (machine_id, tank_number)
);

-- ----------------------------------------------------------------------------
-- 6. TABLA: INGRESOS DE DINERO POR COMPRA REALIZADA (sale_incomes)
-- ----------------------------------------------------------------------------
CREATE TABLE sale_incomes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    machine_id UUID NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
    payment_type payment_type_enum NOT NULL DEFAULT 'monedas',
    amount NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 7. TABLA: HISTORIAL DE VENTAS (sales)
-- ----------------------------------------------------------------------------
CREATE TABLE sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    machine_id UUID NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
    tank_number SMALLINT NOT NULL CHECK (tank_number BETWEEN 1 AND 8),
    product_id UUID REFERENCES products(id),
    price_paid NUMERIC(10, 2) NOT NULL CHECK (price_paid >= 0),
    liters_purchased NUMERIC(8, 3) NOT NULL CHECK (liters_purchased >= 0),
    liters_flow_sensor NUMERIC(8, 4) NOT NULL CHECK (liters_flow_sensor >= 0),
    tank_liters_before NUMERIC(8, 3) NOT NULL,
    tank_liters_after NUMERIC(8, 3) NOT NULL,
    status purchase_status_enum NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 8. TABLA: ARQUEOS Y RECOLECCIÓN DE EFECTIVO (money_collections)
-- ----------------------------------------------------------------------------
CREATE TABLE money_collections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    machine_id UUID NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
    payment_type payment_type_enum NOT NULL DEFAULT 'monedas',
    amount_collected NUMERIC(10, 2) NOT NULL CHECK (amount_collected >= 0),
    status collection_status_enum NOT NULL,
    collector_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 9. TABLA: OPERACIONES DE TANQUE - RECARGAS Y PURGAS (tank_operations)
-- ----------------------------------------------------------------------------
CREATE TABLE tank_operations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    machine_id UUID NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
    tank_number SMALLINT NOT NULL CHECK (tank_number BETWEEN 1 AND 8),
    product_id UUID REFERENCES products(id),
    operation_type tank_action_enum NOT NULL,
    tank_liters_before NUMERIC(8, 3) NOT NULL,
    tank_liters_after NUMERIC(8, 3) NOT NULL,
    net_liters NUMERIC(8, 3) GENERATED ALWAYS AS (tank_liters_after - tank_liters_before) STORED,
    technician_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 10. TABLA: REGISTRO DE ALERTAS E INCIDENCIAS (system_alerts)
-- ----------------------------------------------------------------------------
CREATE TABLE system_alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    machine_id UUID NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
    category alert_category_enum NOT NULL,
    alert_type VARCHAR(50) NOT NULL,
    tank_number SMALLINT,
    product_id UUID REFERENCES products(id),
    value_num1 NUMERIC(12, 4),
    value_num2 NUMERIC(12, 4),
    value_string TEXT,
    is_resolved BOOLEAN DEFAULT false,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 11. TABLA: SNAPSHOT DE ESTADO Y SALDO DISPONIBLE (machine_status)
-- ----------------------------------------------------------------------------
CREATE TABLE machine_status (
    machine_id UUID PRIMARY KEY REFERENCES machines(id) ON DELETE CASCADE,
    available_balance NUMERIC(10, 2) DEFAULT 0.00,
    stored_cash_balance NUMERIC(10, 2) DEFAULT 0.00,
    door_open BOOLEAN DEFAULT false,
    coinbox_tampered BOOLEAN DEFAULT false,
    tilt_detected BOOLEAN DEFAULT false,
    last_keepalive_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- AUTOMATIZACIÓN DE AUTENTICACIÓN Y ROLES DE PWA
-- ----------------------------------------------------------------------------

-- Función Auxiliar para verificar rol de Admin evitando recursión en RLS
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger para creación automática de perfil al registrarse con Google Auth / Email
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, avatar_url, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', 'Usuario'),
    NEW.raw_user_meta_data->>'avatar_url',
    'viewer' -- Rol por defecto asignado a nuevos usuarios
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ----------------------------------------------------------------------------
-- VISTAS PARA DASHBOARDS Y REPORTES MENSUALES
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_monthly_sales_report AS
SELECT 
    s.machine_id,
    m.device_id,
    m.name AS machine_name,
    TO_CHAR(s.created_at, 'YYYY-MM') AS month_period,
    COUNT(s.id) FILTER (WHERE s.status = 'success') AS monthly_successful_sales,
    COUNT(s.id) FILTER (WHERE s.status = 'fail') AS monthly_failed_sales,
    COALESCE(SUM(s.price_paid) FILTER (WHERE s.status = 'success'), 0.00) AS monthly_revenue,
    COALESCE(SUM(s.liters_purchased) FILTER (WHERE s.status = 'success'), 0.000) AS monthly_liters_sold
FROM sales s
JOIN machines m ON s.machine_id = m.id
GROUP BY s.machine_id, m.device_id, m.name, TO_CHAR(s.created_at, 'YYYY-MM');

CREATE OR REPLACE VIEW v_monthly_product_performance AS
SELECT 
    TO_CHAR(s.created_at, 'YYYY-MM') AS month_period,
    p.id AS product_id,
    p.name AS product_name,
    COUNT(s.id) AS monthly_transactions,
    COALESCE(SUM(s.liters_purchased), 0.000) AS monthly_liters_dispensed,
    COALESCE(SUM(s.price_paid), 0.00) AS monthly_revenue
FROM sales s
JOIN products p ON s.product_id = p.id
WHERE s.status = 'success'
GROUP BY TO_CHAR(s.created_at, 'YYYY-MM'), p.id, p.name;

CREATE OR REPLACE VIEW v_monthly_revenue_by_payment_type AS
SELECT 
    si.machine_id,
    m.device_id,
    TO_CHAR(si.created_at, 'YYYY-MM') AS month_period,
    si.payment_type,
    COALESCE(SUM(si.amount), 0.00) AS monthly_total_amount,
    COUNT(si.id) AS monthly_transactions_count
FROM sale_incomes si
JOIN machines m ON si.machine_id = m.id
GROUP BY si.machine_id, m.device_id, TO_CHAR(si.created_at, 'YYYY-MM'), si.payment_type;

CREATE OR REPLACE VIEW v_monthly_financial_audit AS
SELECT 
    m.id AS machine_id,
    m.device_id,
    m.name AS machine_name,
    TO_CHAR(COALESCE(s.created_at, mc.created_at, NOW()), 'YYYY-MM') AS month_period,
    COALESCE(SUM(s.price_paid) FILTER (WHERE s.status = 'success'), 0.00) AS monthly_sales_revenue,
    COALESCE(SUM(mc.amount_collected) FILTER (WHERE mc.status = 'success'), 0.00) AS monthly_cash_collected
FROM machines m
LEFT JOIN sales s ON m.id = s.machine_id
LEFT JOIN money_collections mc ON m.id = mc.machine_id
GROUP BY m.id, m.device_id, m.name, TO_CHAR(COALESCE(s.created_at, mc.created_at, NOW()), 'YYYY-MM');

CREATE OR REPLACE VIEW v_monthly_tank_operations AS
SELECT 
    TO_CHAR(top.created_at, 'YYYY-MM') AS month_period,
    m.device_id,
    top.tank_number,
    p.name AS product_name,
    top.operation_type,
    COUNT(top.id) AS monthly_operation_count,
    COALESCE(SUM(ABS(top.net_liters)), 0.000) AS total_volume_handled
FROM tank_operations top
JOIN machines m ON top.machine_id = m.id
LEFT JOIN products p ON top.product_id = p.id
GROUP BY TO_CHAR(top.created_at, 'YYYY-MM'), m.device_id, top.tank_number, p.name, top.operation_type;

-- ----------------------------------------------------------------------------
-- ÍNDICES DE RENDIMIENTO
-- ----------------------------------------------------------------------------
CREATE INDEX idx_sales_month_period ON sales(machine_id, created_at DESC);
CREATE INDEX idx_incomes_month_period ON sale_incomes(machine_id, payment_type, created_at DESC);
CREATE INDEX idx_collections_month_period ON money_collections(machine_id, created_at DESC);
CREATE INDEX idx_alerts_security_tamper ON system_alerts(machine_id, alert_type, created_at DESC);

-- ----------------------------------------------------------------------------
-- ROW LEVEL SECURITY (RLS) EN SUPABASE
-- ----------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE machines ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE machine_tanks ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_incomes ENABLE ROW LEVEL SECURITY;
ALTER TABLE money_collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE tank_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE machine_status ENABLE ROW LEVEL SECURITY;

-- Políticas para public.profiles
CREATE POLICY "Permitir lectura del propio perfil" 
ON public.profiles FOR SELECT TO authenticated 
USING (auth.uid() = id);

CREATE POLICY "Administradores pueden ver todos los perfiles" 
ON public.profiles FOR SELECT TO authenticated 
USING (public.is_admin());

CREATE POLICY "Permitir actualizar propio perfil" 
ON public.profiles FOR UPDATE TO authenticated 
USING (auth.uid() = id)
WITH CHECK (
  role = (SELECT role FROM public.profiles WHERE id = auth.uid())
);

-- Políticas operativas
CREATE POLICY "Lectura autenticada para Dashboard" ON sales FOR SELECT TO authenticated USING (true);
CREATE POLICY "Lectura pública para catálogo de productos" ON products FOR SELECT TO authenticated, anon USING (true);
CREATE POLICY "Lectura para tanques" ON machine_tanks FOR SELECT TO authenticated USING (true);
CREATE POLICY "Lectura para alertas" ON system_alerts FOR SELECT TO authenticated USING (true);
