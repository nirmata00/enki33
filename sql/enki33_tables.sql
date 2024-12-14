-- Tabla de usuarios
CREATE TABLE public.app_user (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    email varchar(255) NOT NULL UNIQUE,
    name varchar(100) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

-- Tabla de organizaciones
CREATE TABLE public.organization (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    code varchar(20) NOT NULL UNIQUE,
    name varchar(100) NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    CONSTRAINT organization_name_unique UNIQUE (name)
);

-- Tabla de monedas
CREATE TABLE public.currency (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    code varchar(3) NOT NULL UNIQUE,
    name varchar(50) NOT NULL,
    symbol varchar(5),
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

-- Tabla de jarras de presupuesto
CREATE TABLE public.budget_jar (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name varchar(50) NOT NULL,
    description text,
    percentage numeric(5,2) NOT NULL,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    CONSTRAINT check_percentage CHECK (percentage >= 0 AND percentage <= 100)
);

-- Tabla de categorías
CREATE TABLE public.category (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name varchar(50) NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

-- Tabla de subcategorías
CREATE TABLE public.sub_category (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name varchar(50) NOT NULL,
    description text,
    category_id uuid NOT NULL REFERENCES public.category(id) ON DELETE CASCADE,
    budget_jar_id uuid NOT NULL REFERENCES public.budget_jar(id) ON DELETE CASCADE,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

-- Tabla de histórico de cambios en subcategorías
CREATE TABLE public.sub_category_history (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    sub_category_id uuid NOT NULL REFERENCES public.sub_category(id) ON DELETE CASCADE,
    old_category_id uuid REFERENCES public.category(id) ON DELETE SET NULL,
    new_category_id uuid REFERENCES public.category(id) ON DELETE SET NULL,
    old_budget_jar_id uuid REFERENCES public.budget_jar(id) ON DELETE SET NULL,
    new_budget_jar_id uuid REFERENCES public.budget_jar(id) ON DELETE SET NULL,
    change_date timestamptz DEFAULT CURRENT_TIMESTAMP,
    change_type varchar(20) NOT NULL CHECK (change_type IN ('CATEGORY_CHANGE', 'JAR_CHANGE', 'BOTH'))
);

-- Tabla de tipos de transacción
CREATE TABLE public.transaction_type (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name varchar(50) NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

-- Tabla de medios de transacción
CREATE TABLE public.transaction_medium (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name varchar(50) NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

-- Tabla de cuentas
CREATE TABLE public.account (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name varchar(100) NOT NULL,
    description text,
    initial_balance numeric(15,2) DEFAULT 0,
    currency_id uuid NOT NULL REFERENCES public.currency(id) ON DELETE CASCADE,
    is_active boolean DEFAULT true,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

-- Tabla de períodos
CREATE TABLE public.period (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    start_date date NOT NULL,
    end_date date NOT NULL,
    name varchar(50) NOT NULL,
    is_closed boolean DEFAULT false,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_period_dates CHECK (end_date >= start_date)
);

-- Tabla de ingresos por período
CREATE TABLE public.period_income (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    period_id uuid NOT NULL REFERENCES public.period(id) ON DELETE CASCADE,
    total_income numeric(15,2) NOT NULL,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    CONSTRAINT unique_period_income UNIQUE (period_id),
    CONSTRAINT check_income_positive CHECK (total_income >= 0)
);

-- Tabla de presupuestos por jarra y período
CREATE TABLE public.jar_period_budget (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    period_id uuid NOT NULL REFERENCES public.period(id) ON DELETE CASCADE,
    budget_jar_id uuid NOT NULL REFERENCES public.budget_jar(id) ON DELETE CASCADE,
    calculated_amount numeric(15,2) NOT NULL,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_jar_period UNIQUE (period_id, budget_jar_id),
    CONSTRAINT check_amount_positive CHECK (calculated_amount >= 0)
);

-- Tabla de transacciones
CREATE TABLE public.transaction (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    registered_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    date date NOT NULL,
    amount numeric(15, 2) NOT NULL,
    currency_id uuid NOT NULL REFERENCES public.currency(id) ON DELETE CASCADE,
    organization_id uuid NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
    tags jsonb,
    notes text,
    reference varchar(100),
    category uuid NOT NULL REFERENCES public.category(id) ON DELETE CASCADE,
    sub_category uuid NOT NULL REFERENCES public.sub_category(id) ON DELETE CASCADE,
    account uuid NOT NULL REFERENCES public.account(id) ON DELETE CASCADE,
    transaction_type uuid NOT NULL REFERENCES public.transaction_type(id) ON DELETE CASCADE,
    transaction_medium uuid REFERENCES public.transaction_medium(id) ON DELETE CASCADE,
    is_expense boolean NOT NULL DEFAULT true,
    is_recurrent boolean NOT NULL DEFAULT false,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    CONSTRAINT check_amount_not_zero CHECK (amount != 0)
);


-- Crear índices
CREATE INDEX idx_transaction_organization_id ON public.transaction(organization_id);
CREATE INDEX idx_transaction_date ON public.transaction(date);
CREATE INDEX idx_transaction_user_id ON public.transaction(user_id);
CREATE INDEX idx_transaction_account ON public.transaction(account);
CREATE INDEX idx_transaction_category ON public.transaction(category);
CREATE INDEX idx_transaction_sub_category ON public.transaction(sub_category);
CREATE INDEX idx_transaction_is_recurrent ON public.transaction(is_recurrent);