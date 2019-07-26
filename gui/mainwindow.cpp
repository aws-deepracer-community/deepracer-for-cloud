#include "mainwindow.h"
#include "ui_mainwindow.h"

#include <QTextEdit>
#include <QPushButton>

//sudo apt-get install libqt5svg5*

MainWindow::MainWindow(QWidget *parent) :
    QMainWindow(parent),
    ui(new Ui::MainWindow)
{
    ui->setupUi(this);
}

MainWindow::~MainWindow()
{
    delete ui;
}

void MainWindow::on_start_button_clicked()
{

}

void MainWindow::on_save_button_clicked()
{

}

void MainWindow::on_restart_button_clicked()
{

}

void MainWindow::on_reward_function_textChanged()
{

}
