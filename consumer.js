/**
 * MQTT Consumer & Supabase Synchronizer
 * Proyecto: Vending Machine Productos de Limpieza (ESP32 Zephyr)
 * Autor: acovarrubiasd2500@alumno.ipn.mx
 */

require('dotenv').config();
const mqtt = require('mqtt');
const { createClient } = require('@supabase/supabase-js');

// Configuración de Supabase (requiere Service Role Key para escrituras automáticas)
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error('❌ Error: SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY no están configurados en el archivo .env');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

// Configuración del Broker MQTT
const mqttBrokerHost = process.env.MQTT_BROKER_HOST || 'broker.hivemq.com';
const mqttBrokerPort = process.env.MQTT_BROKER_PORT || 1883;
const mqttUrl = `mqtt://${mqttBrokerHost}:${mqttBrokerPort}`;

console.log(`🔌 Conectando al broker MQTT en ${mqttUrl}...`);
const client = mqtt.connect(mqttUrl, {
  clientId: `supabase_consumer_${Math.random().toString(16).substring(2, 8)}`,
  clean: true,
  reconnectPeriod: 5000,
});

client.on('connect', () => {
  console.log('✅ Conectado exitosamente al broker MQTT.');

  // Suscribirse a todos los tópicos relevantes de las máquinas (ej. VM001/income, VM001/sales, etc.)
  const topics = [
    '+/income',
    '+/sales',
    '+/product',
    '+/actions',
    '+/money_collection',
    '+/alerts',
    '+/telemetry/security',
  ];

  topics.forEach((t) => {
    client.subscribe(t, (err) => {
      if (!err) {
        console.log(`📡 Suscrito al tópico: ${t}`);
      } else {
        console.error(`❌ Error al suscribirse a ${t}:`, err);
      }
    });
  });
});

client.on('message', async (topic, message) => {
  const payloadStr = message.toString();
  const parts = topic.split('/');
  const deviceId = parts[0];
  const subTopic = parts.slice(1).join('/');

  try {
    const data = JSON.parse(payloadStr);

    // Obtener el ID interno de la máquina en Supabase
    let { data: machine } = await supabase
      .from('machines')
      .select('id')
      .eq('device_id', deviceId)
      .single();

    if (!machine) {
      // Si la máquina no existe en la BD, la registramos automáticamente
      const { data: newMachine, error: regErr } = await supabase
        .from('machines')
        .insert([{ device_id: deviceId, name: `Máquina Expendedora ${deviceId}` }])
        .select('id')
        .single();

      if (regErr) {
        console.error(`❌ Error registrando máquina ${deviceId}:`, regErr);
        return;
      }
      machine = newMachine;
    }

    const machineId = machine.id;

    // Procesar según el tópico MQTT
    switch (subTopic) {
      case 'income':
        // Pago por compra realizada
        await supabase.from('sale_incomes').insert([
          {
            machine_id: machineId,
            payment_type: data.type || 'monedas',
            amount: data.amount,
          },
        ]);
        console.log(`💰 Ingreso registrado [${deviceId}]: $${data.amount} (${data.type})`);
        break;

      case 'sales':
        // Venta / surtido finalizado
        await supabase.from('sales').insert([
          {
            machine_id: machineId,
            tank_number: data.tank,
            price_paid: data.price_paid,
            liters_purchased: data.liters_purchased,
            liters_flow_sensor: data.liters_flow_sensor,
            tank_liters_before: data.tank_liters_before,
            tank_liters_after: data.tank_liters_after,
            status: data.purchase_status,
          },
        ]);
        console.log(`🛒 Venta registrada [${deviceId}]: Tanque ${data.tank} - ${data.purchase_status}`);
        break;

      case 'product':
        // Actualización de stock en tanque
        await supabase
          .from('machine_tanks')
          .update({
            current_liters: data.liters,
            is_above_minimum: data.above_minimum,
            updated_at: new Date().toISOString(),
          })
          .eq('machine_id', machineId)
          .eq('tank_number', data.tank);
        console.log(`🛢️ Stock actualizado [${deviceId}]: Tanque ${data.tank} -> ${data.liters} L`);
        break;

      case 'actions':
        // Recarga o Purga de tanque
        await supabase.from('tank_operations').insert([
          {
            machine_id: machineId,
            tank_number: data.tank,
            operation_type: data.operation_type,
            tank_liters_before: data.tank_liters_before,
            tank_liters_after: data.tank_liters_after,
          },
        ]);
        console.log(`🔧 Operación registrada [${deviceId}]: ${data.operation_type} en Tanque ${data.tank}`);
        break;

      case 'money_collection':
        // Retiro de monedas / Corte de caja
        await supabase.from('money_collections').insert([
          {
            machine_id: machineId,
            payment_type: data.type || 'monedas',
            amount_collected: data.amount,
            status: data.status,
          },
        ]);
        console.log(`💵 Corte de caja [${deviceId}]: $${data.amount} - ${data.status}`);
        break;

      case 'alerts':
        // Alertas e incidencias (Violación de caja, tilt, etc.)
        await supabase.from('system_alerts').insert([
          {
            machine_id: machineId,
            category: data.category || 'security',
            alert_type: data.type,
            tank_number: data.tank || null,
            value_num1: data.value1 || null,
            value_num2: data.value2 || null,
            value_string: data.value_string || null,
          },
        ]);
        console.log(`🚨 ALERTA [${deviceId}]: ${data.type} (${data.category})`);
        break;

      case 'telemetry/security':
        // Snapshot de estado y saldo disponible sin reclamar
        await supabase.from('machine_status').upsert([
          {
            machine_id: machineId,
            available_balance: data.available_balance || 0.0,
            door_open: data.door_open || false,
            coinbox_tampered: data.coinbox_tampered || false,
            tilt_detected: data.tilt_detected || false,
            last_keepalive_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          },
        ]);
        console.log(`📊 Telemetría/Saldo [${deviceId}]: Disponible = $${data.available_balance}`);
        break;
    }
  } catch (err) {
    console.error(`⚠️ Error procesando mensaje MQTT en ${topic}:`, err.message);
  }
});

client.on('error', (err) => {
  console.error('❌ Error de conexión MQTT:', err);
});
