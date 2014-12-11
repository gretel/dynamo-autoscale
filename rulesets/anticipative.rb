# scale up
reads  last: 2, greater_than: '90%', scale: { on: :consumed, by: 1.8 }
writes last: 2, greater_than: '90%', scale: { on: :consumed, by: 1.8 }

reads  last: 2, greater_than: '75%', scale: { on: :consumed, by: 1.6 }
writes last: 2, greater_than: '75%', scale: { on: :consumed, by: 1.6 }

# scale down
reads  for:  2.hours, less_than: '10%', min: 10, scale: { on: :consumed, by: 1.8 }
writes for:  2.hours, less_than: '10%', min: 10, scale: { on: :consumed, by: 1.8 }

reads  for:  2.hours, less_than: '25%', min: 10, scale: { on: :consumed, by: 1.6 }
writes for:  2.hours, less_than: '25%', min: 10, scale: { on: :consumed, by: 1.6 }

# table-sepcific
table 'cash_flow' do
  reads  last: 2, greater_than: '60%', scale: { on: :consumed, by: 2.0 }
  writes last: 2, greater_than: '60%', scale: { on: :consumed, by: 2.0 }

  reads  for:  3.hours, less_than: '60%', min: 20, scale: { on: :consumed, by: 1.5 }
  writes for:  3.hours, less_than: '30%', min: 20, scale: { on: :consumed, by: 2.0 }
end
