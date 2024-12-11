-- Version: 1.3  
-- Date: 2024-02-07  
-- Description: Database tables and relationships definitions  

-- 1. Configuración Inicial  


-- 2. Tablas de Configuración Base  
CREATE TABLE public.currency (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    code varchar(3) NOT NULL UNIQUE,  
    name varchar(50) NOT NULL,  
    symbol varchar(5) NOT NULL,  
    is_default boolean DEFAULT false,  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP  
);  



CREATE TABLE public.app_user (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    email varchar(255) NOT NULL,  
    name varchar(100) NOT NULL,  
    role text DEFAULT 'authenticated' NOT NULL,  
    phone varchar(20),  
    confirmed_at timestamptz,  
    last_sign_in_at timestamptz,  
    last_login timestamptz,  
    raw_app_meta_data jsonb,  
    raw_user_meta_data jsonb,  
    is_super_admin boolean DEFAULT false NOT NULL,  
    phone_confirmed_at timestamptz,  
    email_confirmed_at timestamptz,  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,  
    CONSTRAINT unique_email UNIQUE (email)  
);  

CREATE TABLE public.account_type (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    name varchar(100) NOT NULL,  
    code varchar(20) NOT NULL,  
    description text,  
    requires_payment_info boolean DEFAULT false,  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,  
    modified_at timestamptz,  
    CONSTRAINT account_type_name_unique UNIQUE (name),  
    CONSTRAINT account_type_code_unique UNIQUE (code),  
    CONSTRAINT valid_account_type CHECK (  
        code IN ('DEBIT', 'CREDIT_CARD', 'LOAN', 'SAVINGS', 'INVESTMENT', 'CASH')  
    )  
);  

CREATE TABLE public.account (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    name varchar(100) NOT NULL,  
    balance numeric(15, 2) DEFAULT 0,  
    account_type uuid NOT NULL REFERENCES public.account_type(id),  
    currency_id uuid NOT NULL REFERENCES public.currency(id),  
    user_id uuid NOT NULL REFERENCES public.app_user(id),  
    interest_rate numeric(5, 2) DEFAULT 0,  
    credit_limit numeric(15, 2),  
    payment_day smallint,  
    cut_day smallint,  
    minimum_payment numeric(15, 2),  
    next_payment_date date,  
    loan_term_months integer,  
    loan_start_date date,  
    loan_end_date date,  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,  
    modified_at timestamptz,  
    CONSTRAINT account_name_unique UNIQUE (name),  
    CONSTRAINT check_balance_positive CHECK (balance >= 0),  
    CONSTRAINT check_interest_rate_positive CHECK (interest_rate >= 0),  
    CONSTRAINT check_payment_day CHECK (payment_day BETWEEN 1 AND 31),  
    CONSTRAINT check_cut_day CHECK (cut_day BETWEEN 1 AND 31),  
    CONSTRAINT check_credit_limit_positive CHECK (credit_limit >= 0),  
    CONSTRAINT check_loan_term_months_positive CHECK (loan_term_months > 0),  
    CONSTRAINT check_loan_dates CHECK (  
        CASE WHEN loan_start_date IS NOT NULL   
             THEN loan_end_date IS NOT NULL AND loan_end_date > loan_start_date  
             ELSE true  
        END  
    )  
);  

-- 3. Tablas de Categorización y Presupuesto  
CREATE TABLE public.budget_jar (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    code varchar(10) NOT NULL UNIQUE,  
    name varchar(100) NOT NULL,  
    description text,  
    percentage numeric(5,2) NOT NULL,  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,  
    CONSTRAINT check_percentage CHECK (percentage >= 0 AND percentage <= 100)  
);  

CREATE TABLE public.category (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    name varchar(100) NOT NULL,  
    description text,  
    budget_jar_id uuid REFERENCES public.budget_jar(id),  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,  
    modified_at timestamptz,  
    CONSTRAINT category_name_unique UNIQUE (name)  
);  

CREATE TABLE public.sub_category (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    name varchar(100) NOT NULL,  
    description text,  
    parent_category uuid NOT NULL REFERENCES public.category(id),  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,  
    modified_at timestamptz  
);  

CREATE TABLE public.period (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    description varchar(100) NOT NULL,  
    from_date date NOT NULL,  
    to_date date NOT NULL,  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,  
    CONSTRAINT period_description_unique UNIQUE (description),  
    CONSTRAINT date_range_unique UNIQUE (from_date, to_date),  
    CONSTRAINT check_date_range CHECK (from_date <= to_date)  
);  

CREATE TABLE public.budget_classification (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    classification varchar(100) NOT NULL,  
    percentage numeric(5, 2),  
    period uuid NOT NULL REFERENCES public.period(id),  
    jar_id uuid REFERENCES public.budget_jar(id),  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,  
    modified_at timestamptz,  
    CONSTRAINT budget_classification_unique UNIQUE (classification, period)  
);  

CREATE TABLE public.budget (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    classification uuid NOT NULL REFERENCES public.budget_classification(id),  
    available numeric(15, 2) NOT NULL DEFAULT 0,  
    real numeric(15, 2) NOT NULL DEFAULT 0,  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,  
    modified_at timestamptz,  
    CONSTRAINT check_amounts_positive CHECK (available >= 0 AND real >= 0)  
);  

-- 4. Tablas de Transacciones  
CREATE TABLE public.transaction_type (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    name varchar(20) NOT NULL,  
    description text,  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,  
    modified_at timestamptz,  
    CONSTRAINT valid_transaction_type CHECK (name IN ('INGRESO', 'EGRESO', 'TRANSFERENCIA'))  
);  

CREATE TABLE public.transaction_medium (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    name varchar(20) NOT NULL,  
    description text,  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,  
    modified_at timestamptz,  
    CONSTRAINT valid_transaction_medium CHECK (  
        name IN ('EFECTIVO', 'TARJETA_CREDITO', 'TARJETA_DEBITO', 'INTERNA')  
    )  
);  

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
);  

CREATE TABLE public.recurring_transaction (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    transaction_template_id uuid REFERENCES public.transaction(id),  
    frequency interval NOT NULL,  
    start_date date NOT NULL DEFAULT CURRENT_DATE,  
    next_execution_date date NOT NULL,  
    last_execution_date date,  
    end_date date,  
    execution_day smallint,  
    execution_count integer DEFAULT 0,  
    max_executions integer,  
    status varchar(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'PAUSED', 'CANCELLED')),  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,  
    modified_at timestamptz,  
    CONSTRAINT check_date_range CHECK (  
        start_date <= end_date OR end_date IS NULL  
    ),  
    CONSTRAINT check_execution_day CHECK (  
        execution_day BETWEEN 1 AND 31  
    ),  
    CONSTRAINT check_max_executions CHECK (  
        max_executions IS NULL OR max_executions > 0  
    )  
);  

CREATE TABLE public.account_transfer (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    made_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,  
    from_account uuid NOT NULL REFERENCES public.account(id),  
    to_account uuid NOT NULL REFERENCES public.account(id),  
    amount numeric(15, 2) NOT NULL,  
    description text,  
    reference varchar(100),  
    user_id uuid NOT NULL REFERENCES public.app_user(id),  
    CONSTRAINT check_different_accounts CHECK (from_account != to_account),  
    CONSTRAINT check_transfer_amount_positive CHECK (amount > 0)  
);  

CREATE TABLE public.transaction_period (  
    transaction uuid NOT NULL REFERENCES public.transaction(id),  
    period uuid NOT NULL REFERENCES public.period(id),  
    CONSTRAINT pk_transaction_period PRIMARY KEY (transaction, period)  
);  

-- 5. Tabla para Metas Financieras  
CREATE TABLE public.financial_goal (  
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,  
    user_id uuid REFERENCES public.app_user(id),  
    name varchar(100) NOT NULL,  
    target_amount numeric(15,2) NOT NULL,  
    current_amount numeric(15,2) DEFAULT 0,  
    deadline date,  
    status varchar(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'COMPLETED', 'CANCELLED')),  
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,  
    modified_at timestamptz,  
    CONSTRAINT check_target_amount_positive CHECK (target_amount > 0),  
    CONSTRAINT check_current_amount_positive CHECK (current_amount >= 0)  
);  

-- 6. Índices  
CREATE INDEX idx_transaction_date_account ON public.transaction(date, account);  
CREATE INDEX idx_transaction_organization ON public.transaction(organization);  
CREATE INDEX idx_transaction_period_date ON public.transaction(date);  
CREATE INDEX idx_budget_classification_period ON public.budget_classification(period, classification);  
CREATE INDEX idx_sub_category_name ON public.sub_category(name);  
CREATE INDEX idx_account_name ON public.account(name);  
CREATE INDEX idx_account_balance ON public.account(balance);  
CREATE INDEX idx_transaction_is_expense ON public.transaction(is_expense);  
CREATE INDEX idx_budget_jar_code ON public.budget_jar(code);  
CREATE INDEX idx_account_payment_date ON public.account(next_payment_date);  
CREATE INDEX idx_account_type_code ON public.account_type(code);  
CREATE INDEX idx_transaction_is_recurrent ON public.transaction(is_recurrent);  
CREATE INDEX idx_transaction_organization_id ON public.transaction(organization_id); 

-- 1. Crear tabla de historial de saldos
CREATE TABLE public.account_balance_history (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES public.account(id),
    previous_balance numeric(15, 2) NOT NULL,
    new_balance numeric(15, 2) NOT NULL,
    change_amount numeric(15, 2) NOT NULL,
    transaction_id uuid REFERENCES public.transaction(id),
    transfer_id uuid REFERENCES public.account_transfer(id),
    change_type varchar(20) NOT NULL,
    changed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by uuid NOT NULL REFERENCES public.app_user(id),
    notes text,
    CONSTRAINT check_balance_amounts CHECK (
        previous_balance >= 0 AND 
        new_balance >= 0
    ),
    CONSTRAINT check_change_type CHECK (
        change_type IN ('TRANSACTION', 'TRANSFER', 'ADJUSTMENT', 'INTEREST', 'FEE')
    ),
    CONSTRAINT check_reference_consistency CHECK (
        (change_type = 'TRANSACTION' AND transaction_id IS NOT NULL AND transfer_id IS NULL) OR
        (change_type = 'TRANSFER' AND transfer_id IS NOT NULL AND transaction_id IS NULL) OR
        ((change_type IN ('ADJUSTMENT', 'INTEREST', 'FEE')) AND transaction_id IS NULL AND transfer_id IS NULL)
    )
);

-- 2. Crear índices para optimizar consultas comunes
CREATE INDEX idx_balance_history_account ON public.account_balance_history(account_id);
CREATE INDEX idx_balance_history_date ON public.account_balance_history(changed_at);
CREATE INDEX idx_balance_history_type ON public.account_balance_history(change_type);

-- 3. Crear función para registrar cambios de saldo


-- 7. RLS Policies  
ALTER TABLE public.transaction ENABLE ROW LEVEL SECURITY;  

