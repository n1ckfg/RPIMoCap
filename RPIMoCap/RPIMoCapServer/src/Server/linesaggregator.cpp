/*
 * This file is part of the RPIMoCap (https://github.com/kaajo/RPIMoCap).
 * Copyright (c) 2019 Miroslav Krajicek.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#include "RPIMoCap/Server/linesaggregator.h"

#include <QtDebug>
#include <QThread>

#include <msgpack.hpp>

#include <chrono>

LinesAggregator::LinesAggregator(QObject *parent) : QObject(parent)
{

}

void LinesAggregator::addCamera(const std::shared_ptr<CameraSettings> &camera)
{
    if (!m_clients.contains(camera->id()))
    {
        m_clients.insert(camera->id(), camera);
        m_currentlyReceived.insert(camera->id(), false);
        m_currentlyReceivedPoints.insert(camera->id(), false);
    }
}

void LinesAggregator::removeCamera(const int id)
{
    if (m_clients.contains(id))
    {
        m_clients.remove(id);
        m_currentlyReceived.remove(id);
        m_currentlyReceivedPoints.remove(id);
    }
}

void LinesAggregator::startCalib()
{
    RPIMoCap::CameraParams params = RPIMoCap::CameraParams::computeRPICameraV1Params();
    m_wandCalib = std::make_unique<WandCalibration>(m_clients,params);
}

void LinesAggregator::stopCalib()
{
    m_wandCalib.reset();
}

void LinesAggregator::onMoCapStart(bool start)
{
    for (auto &received : m_currentlyReceived)
    {
        received = false;
    }
    m_currentlines.clear();

    running = start;
    if (start)
    {
        emit trigger({});
    }
}

void LinesAggregator::onLinesReceived(const int clientId, const std::vector<RPIMoCap::Line3D> &lines)
{
    if (m_clients.find(clientId) == m_clients.end())
    {
        return;
    }

    m_currentlines.append(QVector<RPIMoCap::Line3D>::fromStdVector(lines));
    m_currentlyReceived[clientId] = true;

    bool haveAll = true;

    for (auto &received : m_currentlyReceived)
    {
        if (!received)
        {
            haveAll = false;
        }
    }

    if (running && haveAll)
    {
        auto curTime = QTime::currentTime();

        qDebug() << "ms elapsed: " << lastTime.msecsTo(curTime) << " lines received: " << lines.size() << "from client: " << clientId;
        lastTime = curTime;

        for (auto &received : m_currentlyReceived)
        {
            received = false;
        }

        emit trigger({});

        uint64_t currentTime = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::high_resolution_clock::now().time_since_epoch()).count();

        RPIMoCap::Frame frame(currentTime, m_currentlines.toStdVector());
        emit frameReady(frame);
        emit linesReceived(m_currentlines.toStdVector());
        m_currentlines.clear();
    }
}

void LinesAggregator::onPointsReceived(const int clientId, const std::vector<cv::Point2i> &points)
{
    if (m_clients.find(clientId) == m_clients.end())
    {
        return;
    }

    std::vector<cv::Point2f> pointsf;
    for (size_t i = 0; i < points.size(); ++i)
    {
        pointsf.push_back(points[i]);
    }
    m_currentPoints[clientId] = pointsf;

    m_currentlyReceivedPoints[clientId] = true;

    bool haveAll = true;

    for (auto &received : m_currentlyReceivedPoints)
    {
        if (!received)
        {
            haveAll = false;
        }
    }

    if (running && haveAll)
    {
        if (m_wandCalib)
        {
            m_wandCalib->addFrame(m_currentPoints);
        }

        for (auto &received : m_currentlyReceivedPoints)
        {
            received = false;
        }
    }
}
